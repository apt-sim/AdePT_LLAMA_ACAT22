// SPDX-FileCopyrightText: 2022 CERN
// SPDX-License-Identifier: Apache-2.0

#ifndef EXAMPLE_CUH
#define EXAMPLE_CUH

#include "example.h"

#include "llama.hpp"
#include <CopCore/SystemOfUnits.h>
#include <CopCore/Ranluxpp.h>

#include <G4HepEmData.hh>
#include <G4HepEmParameters.hh>
#include <G4HepEmRandomEngine.hh>

#include <VecGeom/base/Vector3D.h>
#include <VecGeom/navigation/NavStateIndex.h>

constexpr int ThreadsPerBlock = 256;

struct RngState {};
struct Energy {};
struct NumIALeft {};
struct InitialRange {};
struct DynamicRangeFactor {};
struct TlimitMin {};
struct Pos {};
struct Dir {};
struct NavState {};

// clang-format off
using Track = llama::Record<
    llama::Field<RngState, RanluxppDouble>,
    llama::Field<Energy, double>,
    llama::Field<NumIALeft, double[3]>,
    llama::Field<InitialRange, double>,
    llama::Field<DynamicRangeFactor, double>,
    llama::Field<TlimitMin, double>,
    llama::Field<Pos, vecgeom::Vector3D<vecgeom::Precision>>,
    llama::Field<Dir, vecgeom::Vector3D<vecgeom::Precision>>,
    llama::Field<NavState, vecgeom::NavStateIndex>>;
// clang-format on

template <typename SecondaryTrack>
__host__ __device__ inline void InitAsSecondary(SecondaryTrack &&track, const vecgeom::Vector3D<Precision> &parentPos,
                                                const vecgeom::NavStateIndex &parentNavState)
{
  // The caller is responsible to branch a new RNG state and to set the energy.
  track(NumIALeft{}, llama::RecordCoord<0>{}) = -1.0;
  track(NumIALeft{}, llama::RecordCoord<1>{}) = -1.0;
  track(NumIALeft{}, llama::RecordCoord<2>{}) = -1.0;

  track(InitialRange{})       = -1.0;
  track(DynamicRangeFactor{}) = -1.0;
  track(TlimitMin{})          = -1.0;

  // A secondary inherits the position of its parent; the caller is responsible
  // to update the directions.
  track(Pos{})      = parentPos;
  auto* dst = &track(NavState{});
  auto* alignedDst = static_cast<vecgeom::NavStateIndex*>(__builtin_assume_aligned(dst, alignof(vecgeom::NavStateIndex)));
  *alignedDst = parentNavState;
}

// Struct for communication between kernels
struct SOAData {
  char *nextInteraction = nullptr;
};

#ifdef __CUDA_ARCH__
// Define inline implementations of the RNG methods for the device.
// (nvcc ignores the __device__ attribute in definitions, so this is only to
// communicate the intent.)
inline __device__ double G4HepEmRandomEngine::flat()
{
  return ((RanluxppDouble *)fObject)->Rndm();
}

inline __device__ void G4HepEmRandomEngine::flatArray(const int size, double *vect)
{
  for (int i = 0; i < size; i++) {
    vect[i] = ((RanluxppDouble *)fObject)->Rndm();
  }
}
#endif

using ParticleCount = unsigned int;

using Mapping = llama::mapping::AoS<llama::ArrayExtentsDynamic<std::size_t, 1>, Track>;
// using Mapping  = llama::mapping::PackedSingleBlobSoA<llama::ArrayExtentsDynamic<std::size_t, 1>, Track>;
// using Mapping  = llama::mapping::AlignedSingleBlobSoA<llama::ArrayExtentsDynamic<std::size_t, 1>, Track>;
// using Mapping  = llama::mapping::MultiBlobSoA<llama::ArrayExtentsDynamic<std::size_t, 1>, Track>;
// using Mapping  = llama::mapping::AoSoA<llama::ArrayExtentsDynamic<std::size_t, 1>, Track, 16>; // try 16, 32, 64, etc.
// using Mapping  = llama::mapping::FieldAccessCount<llama::mapping::AoS<llama::ArrayExtentsDynamic<std::size_t, 1>, Track>,
// unsigned long long, true>;
// using Mapping = llama::mapping::Heatmap<llama::mapping::AoS<llama::ArrayExtentsDynamic<std::size_t, 1>, Track>, 1,
//                                        unsigned long long>;
// using Mapping =
//    llama::mapping::Heatmap<llama::mapping::AoSoA<llama::ArrayExtentsDynamic<std::size_t, 1>, Track, 32>, 1,
//                            unsigned long long>;
// using Mapping =
//     llama::mapping::Heatmap<llama::mapping::PackedSingleBlobSoA<llama::ArrayExtentsDynamic<std::size_t, 1>, Track>,
//     1, unsigned long long>;
// using Mapping  = llama::mapping::Heatmap<llama::mapping::AoS<llama::ArrayExtentsDynamic<std::size_t, 1>, Track>,
//                                        llama::sizeOf<Track>, unsigned long long>;
using BlobType = std::byte *;
using View     = llama::View<Mapping, BlobType>;

// A bundle of pointers to generate particles of an implicit type.
struct ParticleGenerator {
  View fTracks;
  ParticleCount *fNextSlot;
  ParticleCount fMaxSlot;

  __device__ decltype(auto) NextTrack()
  {
    const auto next = atomicAdd(fNextSlot, ParticleCount{1});
    if (next >= fMaxSlot) {
      COPCORE_EXCEPTION("No slot available in ParticleGenerator::NextTrack");
    }
    return fTracks[next];
  }
};

// A bundle of generators for the three particle types.
struct Secondaries {
  ParticleGenerator electrons;
  ParticleGenerator positrons;
  ParticleGenerator gammas;
};

// Kernels in different TUs.
__global__ void TransportElectrons(View electrons, const ParticleCount *electronsCount, Secondaries secondaries,
                                   GlobalScoring *globalScoring, ScoringPerVolume *scoringPerVolume,
                                   SOAData const soaData);
__global__ void TransportPositrons(View positrons, const ParticleCount *electronsCount, Secondaries secondaries,
                                   GlobalScoring *globalScoring, ScoringPerVolume *scoringPerVolume,
                                   SOAData const soaData);

__global__ void TransportGammas(View gammas, const ParticleCount *gammasCount, Secondaries secondaries,
                                GlobalScoring *globalScoring, ScoringPerVolume *scoringPerVolume,
                                SOAData const soaData);

/// Run an interaction on the particles in soaData whose `nextInteraction` matches the ProcessIndex.
/// The specific interaction that's run is defined by `interactionFunction`.
template <int ProcessIndex, typename Func, typename... Args>
__device__ void InteractionLoop(Func interactionFunction, const ParticleCount *count, SOAData const soaData,
                                Args &&...args)
{
  constexpr unsigned int sharedSize = 8192;
  __shared__ int candidates[sharedSize];
  __shared__ unsigned int counter;
  __shared__ int threadsRunning;
  counter               = 0;
  threadsRunning        = 0;
  const auto activeSize = *count;
#ifndef NDEBUG
  __shared__ unsigned int todoCounter;
  __shared__ unsigned int particlesDone;
  todoCounter   = 0;
  particlesDone = 0;
  __syncthreads();
  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < activeSize; i += blockDim.x * gridDim.x) {
    const auto winnerProcess = soaData.nextInteraction[i];
    if (winnerProcess == ProcessIndex) atomicAdd(&todoCounter, 1);
  }
#endif

  __syncthreads();

  int i     = blockIdx.x * blockDim.x + threadIdx.x;
  bool done = false;
  do {
    while (i < activeSize && counter < sharedSize - blockDim.x) {
      if (soaData.nextInteraction[i] == ProcessIndex) {
        const auto destination  = atomicAdd(&counter, 1);
        candidates[destination] = i;
      }
      i += blockDim.x * gridDim.x;
    }

    if (i < activeSize) {
      atomicExch(&threadsRunning, 1);
    }

    __syncthreads();
    done = !threadsRunning;

#ifndef NDEBUG
    if (threadIdx.x == 0) {
      atomicAdd(&particlesDone, counter);
    }
    assert(counter < sharedSize);
    __syncthreads();
#endif

    for (int j = threadIdx.x; j < counter; j += blockDim.x) {
      const auto soaSlot = candidates[j];
      interactionFunction(soaSlot, soaData, std::forward<Args>(args)...);
    }

    __syncthreads();
    counter        = 0;
    threadsRunning = 0;
    __syncthreads();
  } while (!done);

  assert(particlesDone == todoCounter);
}

__global__ void IonizationEl(View particles, const ParticleCount *electronsCount, Secondaries secondaries,
                             GlobalScoring *globalScoring, ScoringPerVolume *scoringPerVolume, SOAData const soaData);
__global__ void BremsstrahlungEl(View particles, const ParticleCount *electronsCount, Secondaries secondaries,
                                 GlobalScoring *globalScoring, ScoringPerVolume *scoringPerVolume,
                                 SOAData const soaData);

__global__ void IonizationPos(View particles, const ParticleCount *electronsCount, Secondaries secondaries,
                              GlobalScoring *globalScoring, ScoringPerVolume *scoringPerVolume, SOAData const soaData);
__global__ void BremsstrahlungPos(View particles, const ParticleCount *electronsCount, Secondaries secondaries,
                                  GlobalScoring *globalScoring, ScoringPerVolume *scoringPerVolume,
                                  SOAData const soaData);
__global__ void AnnihilationPos(View particles, const ParticleCount *electronsCount, Secondaries secondaries,
                                GlobalScoring *globalScoring, ScoringPerVolume *scoringPerVolume,
                                SOAData const soaData);

__global__ void PairCreation(View particles, const ParticleCount *electronsCount, Secondaries secondaries,
                             GlobalScoring *globalScoring, ScoringPerVolume *scoringPerVolume, SOAData const soaData);
__global__ void ComptonScattering(View particles, const ParticleCount *electronsCount, Secondaries secondaries,
                                  GlobalScoring *globalScoring, ScoringPerVolume *scoringPerVolume,
                                  SOAData const soaData);
__global__ void PhotoelectricEffect(View particles, const ParticleCount *electronsCount, Secondaries secondaries,
                                    GlobalScoring *globalScoring, ScoringPerVolume *scoringPerVolume,
                                    SOAData const soaData);

// Constant data structures from G4HepEm accessed by the kernels.
// (defined in TestEm3.cu)
extern __constant__ __device__ struct G4HepEmParameters g4HepEmPars;
extern __constant__ __device__ struct G4HepEmData g4HepEmData;

extern __constant__ __device__ int *MCIndex;

// constexpr vecgeom::Precision BzFieldValue = 3.8 * copcore::units::tesla;
constexpr vecgeom::Precision BzFieldValue = 0;

#endif
