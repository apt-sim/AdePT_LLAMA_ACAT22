cmake_minimum_required(VERSION 3.18)

project(AdeptLLAMA LANGUAGES CXX CUDA)

add_subdirectory(AdePT EXCLUDE_FROM_ALL)

if (NOT TARGET G4HepEm::g4HepEm)
    message(FATAL_ERROR "G4HepEm is required. Did you checkout submodules recursively?")
endif ()

# for some reason, we need to repeat this here from AdePT's CMakeLists.txt for VecGeom to be available
set(VecGeom_VERSION 1.1.20)
find_package(VecGeom ${VecGeom_VERSION} REQUIRED)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR})
add_subdirectory(Example19_baseline)
add_subdirectory(Example19_llama)
add_subdirectory(Example19_llama_db)
add_subdirectory(Example19_llama_trace)
