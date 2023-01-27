set(TargetName example19_baseline)
add_executable(${TargetName} main.cpp main.cu electrons.cu gammas.cu)
target_link_libraries(${TargetName} PRIVATE
    AdePT CopCore::CopCore VecGeom::vecgeom VecGeom::vecgeomcuda_static VecGeom::vgdml
    ${Geant4_LIBRARIES} G4HepEm::g4HepEmData G4HepEm::g4HepEmInit G4HepEm::g4HepEmRun CUDA::cudart)
set_target_properties(${TargetName} PROPERTIES CUDA_SEPARABLE_COMPILATION ON CUDA_RESOLVE_DEVICE_SYMBOLS ON)
