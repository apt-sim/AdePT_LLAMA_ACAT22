# AdePT LLAMA examples for LLAMA PhD thesis

This repository provides examples using [AdePT](https://github.com/apt-sim/AdePT)
and [LLAMA](https://github.com/alpaka-group/llama)
which provided the basis for our contribution to the [ACAT22](https://indico.cern.ch/event/1106990/) workshop.
The slides of our talk are available [here](https://indico.cern.ch/event/1106990/contributions/4991259/).

This repository offers 4 additional examples for AdePT.
All of them are derived from the original Example19, but the track array is managed by LLAMA.
They are called:

- example19_baseline
- example19_llama
- example19_llama_db
- example19_llama_trace

LLAMA allows us to arbitrarily change the data layout without needing to rewrite or change an algorithm using that data.
To switch the data layout, you just need to change the definition of the LLAMA mapping.
A couple of mappings are defined in `example.cuh`
and you can try them out by (un-)commenting the corresponding alias declarations (`using Mapping = ...`).

The following data layouts can be tested directly:

* AoS
* PackedSingleBlobSoA
* AlignedSingleBlobSoA
* MultiBlobSoA
* AoSoAN (with arbitrary N)
* FieldAccessCount (although you will have more accurate results when using the example especially preparted for tracing)
* Heatmap (AoS)
* Heatmap (AoSoA32)
* Heatmap (PackedSingleBlobSoA)
* Heatmap (AoS with slot granularity)

You are free to make up your own data layouts!
Please refer to the [LLAMA mappings documentation](https://llama-doc.readthedocs.io/en/latest/pages/mappings.html)
for further information.
Please refer to the documentation of [Example 19](https://github.com/apt-sim/AdePT/tree/master/examples/Example19/README.md)
for further information on the capabilities of this example
and a detailed description of what the individual kernels do.

## Compiling

- git clone with recursive submodules

- install VecCore
- install VecGeom with cmake options: `-DVECGEOM_GDML=ON -DVECGEOM_VECTOR=empty -DVECGEOM_ENABLE_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=70`
- install Geant4 with cmake options: `-DGEANT4_USE_GDML=ON -DGEANT4_INSTALL_DATA=ON -DCMAKE_INSTALL_RPATH='$ORIGIN'`
- setup Geant4 data files: `geant4-config --datasets | awk '{ printf "export %s=%s\n", $2, $3 }'` and add the output to `~/.bashrc`
- install Boost (required by LLAMA)
- install fmt (required by LLAMA)
- build the examples with cmake options: `-DCMAKE_CUDA_ARCHITECTURES=70`

## Benchmark

To get the average runtime over 5 runs (as we did for the talk/proceedings),
run from the cmake build directory:
```
for i in $(seq 5); do \
./example19_xxx -particles 10000 -batch 1000 -gdml_file ../AdePT/examples/Example14/macros/testEm3.gdml -gunpos -220,0,0 -gundir 1,0,0 \
| grep Run; done | awk '/Run time/{print; x+=$3; xsq+=$3*$3; next} END{print "Mean: " x/NR; print "Stddev: " sqrt(xsq/NR - x*x/NR/NR)}'
```
Replace `example19_xxx` by one of the abovementioned examples.
