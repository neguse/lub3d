# Build sokol-shdc as a library
message(STATUS "Building sokol-shdc library")

set(SHDC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/deps/sokol-tools)
set(SHDC_EXT ${SHDC_DIR}/ext)
set(SHDC_SRC ${SHDC_DIR}/src/shdc)

# C++20 required for sokol-shdc
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Include fips compatibility
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/fips_compat.cmake)

# getopt
add_library(shdc_getopt STATIC
    ${SHDC_EXT}/getopt/src/getopt.c
)
target_include_directories(shdc_getopt PUBLIC ${SHDC_EXT}/getopt/include)

# pystring
add_library(shdc_pystring STATIC
    ${SHDC_EXT}/pystring/pystring.cpp
)
target_include_directories(shdc_pystring PUBLIC ${SHDC_EXT}/pystring)

# fmt
add_library(shdc_fmt STATIC
    ${SHDC_EXT}/fmt/src/format.cc
)
target_compile_definitions(shdc_fmt PUBLIC FMT_UNICODE=0)
target_include_directories(shdc_fmt PUBLIC ${SHDC_EXT}/fmt/include)

# SPIRV-Tools (exclude fuzz, reduce, link directories)
file(GLOB SPIRV_TOOLS_SOURCES
    ${SHDC_EXT}/SPIRV-Tools/source/*.cpp
)
file(GLOB SPIRV_TOOLS_UTIL ${SHDC_EXT}/SPIRV-Tools/source/util/*.cpp)
file(GLOB SPIRV_TOOLS_VAL ${SHDC_EXT}/SPIRV-Tools/source/val/*.cpp)
file(GLOB SPIRV_TOOLS_OPT ${SHDC_EXT}/SPIRV-Tools/source/opt/*.cpp)
list(APPEND SPIRV_TOOLS_SOURCES ${SPIRV_TOOLS_UTIL} ${SPIRV_TOOLS_VAL} ${SPIRV_TOOLS_OPT})
add_library(shdc_spirv_tools STATIC ${SPIRV_TOOLS_SOURCES})
target_include_directories(shdc_spirv_tools PUBLIC
    ${SHDC_EXT}/generated
    ${SHDC_EXT}/SPIRV-Tools
    ${SHDC_EXT}/SPIRV-Tools/include
    ${SHDC_EXT}/SPIRV-Headers/include
)
if(MSVC)
    target_compile_definitions(shdc_spirv_tools PUBLIC _SCL_SECURE_NO_WARNINGS)
endif()

# glslang
if(WIN32)
    file(GLOB GLSLANG_OSDEP ${SHDC_EXT}/glslang/glslang/OSDependent/Windows/*.cpp)
    list(FILTER GLSLANG_OSDEP EXCLUDE REGEX "main\\.cpp$")
elseif(EMSCRIPTEN)
    file(GLOB GLSLANG_OSDEP ${SHDC_EXT}/glslang/glslang/OSDependent/Unix/*.cpp)
else()
    file(GLOB GLSLANG_OSDEP ${SHDC_EXT}/glslang/glslang/OSDependent/Unix/*.cpp)
endif()
file(GLOB_RECURSE GLSLANG_SOURCES
    ${SHDC_EXT}/glslang/glslang/GenericCodeGen/*.cpp
    ${SHDC_EXT}/glslang/glslang/MachineIndependent/*.cpp
    ${SHDC_EXT}/glslang/glslang/ResourceLimits/*.cpp
    ${SHDC_EXT}/glslang/SPIRV/*.cpp
)
# Remove HLSL
list(FILTER GLSLANG_SOURCES EXCLUDE REGEX "hlsl")
add_library(shdc_glslang STATIC ${GLSLANG_SOURCES} ${GLSLANG_OSDEP})
target_include_directories(shdc_glslang PUBLIC ${SHDC_EXT}/glslang)
target_include_directories(shdc_glslang PRIVATE ${SHDC_EXT}/glslang/glslang ${SHDC_EXT}/generated)
target_compile_definitions(shdc_glslang PRIVATE ENABLE_OPT=1)
if(WIN32)
    target_compile_definitions(shdc_glslang PRIVATE GLSLANG_OSINCLUDE_WIN32)
elseif(EMSCRIPTEN)
    target_compile_definitions(shdc_glslang PRIVATE GLSLANG_OSINCLUDE_UNIX)
else()
    target_compile_definitions(shdc_glslang PRIVATE GLSLANG_OSINCLUDE_UNIX)
endif()
target_link_libraries(shdc_glslang shdc_spirv_tools)
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(shdc_glslang PRIVATE -Wno-sign-compare)
endif()

# SPIRV-Cross
add_library(shdc_spirv_cross STATIC
    ${SHDC_EXT}/SPIRV-Cross/spirv_cross.cpp
    ${SHDC_EXT}/SPIRV-Cross/spirv_parser.cpp
    ${SHDC_EXT}/SPIRV-Cross/spirv_cross_parsed_ir.cpp
    ${SHDC_EXT}/SPIRV-Cross/spirv_cfg.cpp
    ${SHDC_EXT}/SPIRV-Cross/spirv_glsl.cpp
    ${SHDC_EXT}/SPIRV-Cross/spirv_msl.cpp
    ${SHDC_EXT}/SPIRV-Cross/spirv_hlsl.cpp
    ${SHDC_EXT}/SPIRV-Cross/spirv_reflect.cpp
    ${SHDC_EXT}/SPIRV-Cross/spirv_cross_util.cpp
)
target_include_directories(shdc_spirv_cross PUBLIC ${SHDC_EXT}/SPIRV-Cross)
if(MSVC)
    target_compile_definitions(shdc_spirv_cross PUBLIC _SCL_SECURE_NO_WARNINGS)
    target_compile_options(shdc_spirv_cross PUBLIC /wd4715)
endif()

# tint
file(GLOB_RECURSE TINT_SOURCES ${SHDC_EXT}/tint-extract/src/tint/*.cc)
add_library(shdc_tint STATIC ${TINT_SOURCES})
target_include_directories(shdc_tint PUBLIC ${SHDC_EXT}/tint-extract ${SHDC_EXT}/tint-extract/include)
target_compile_definitions(shdc_tint PUBLIC TINT_BUILD_SPV_READER=1 TINT_BUILD_WGSL_WRITER=1)
target_link_libraries(shdc_tint shdc_spirv_tools)
if(MSVC)
    target_compile_options(shdc_tint PRIVATE /wd4715)
endif()

# sokol-shdc library (without main.cc)
add_library(sokol_shdc_lib STATIC
    ${SHDC_SRC}/args.cc
    ${SHDC_SRC}/bytecode.cc
    ${SHDC_SRC}/input.cc
    ${SHDC_SRC}/reflection.cc
    ${SHDC_SRC}/spirv.cc
    ${SHDC_SRC}/spirvcross.cc
    ${SHDC_SRC}/util.cc
    ${SHDC_SRC}/generators/generate.cc
    ${SHDC_SRC}/generators/bare.cc
    ${SHDC_SRC}/generators/sokold.cc
    ${SHDC_SRC}/generators/sokolnim.cc
    ${SHDC_SRC}/generators/sokolodin.cc
    ${SHDC_SRC}/generators/sokolrust.cc
    ${SHDC_SRC}/generators/sokolzig.cc
    ${SHDC_SRC}/generators/yaml.cc
)
target_include_directories(sokol_shdc_lib PUBLIC ${SHDC_SRC} ${SHDC_DIR}/src)
target_link_libraries(sokol_shdc_lib
    shdc_getopt
    shdc_pystring
    shdc_fmt
    shdc_glslang
    shdc_spirv_cross
    shdc_tint
)
set_target_properties(sokol_shdc_lib PROPERTIES CXX_STANDARD 20)
