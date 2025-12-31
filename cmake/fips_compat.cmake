# fips compatibility layer for building sokol-tools without fips

# Platform detection
if(WIN32)
    set(FIPS_WINDOWS ON)
    set(FIPS_POSIX OFF)
elseif(APPLE)
    set(FIPS_MACOS ON)
    set(FIPS_POSIX ON)
else()
    set(FIPS_LINUX ON)
    set(FIPS_POSIX ON)
endif()

if(MSVC)
    set(FIPS_MSVC ON)
elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    set(FIPS_CLANG ON)
elseif(CMAKE_CXX_COMPILER_ID MATCHES "GNU")
    set(FIPS_GCC ON)
endif()

# Current library being built
set(_FIPS_CURRENT_LIB "")
set(_FIPS_CURRENT_SOURCES "")
set(_FIPS_CURRENT_DIR "")

macro(fips_setup)
    # Nothing needed
endmacro()

macro(fips_ide_group name)
    # IDE organization - ignore for now
endmacro()

macro(fips_begin_lib name)
    set(_FIPS_CURRENT_LIB ${name})
    set(_FIPS_CURRENT_SOURCES "")
endmacro()

macro(fips_end_lib)
    add_library(${_FIPS_CURRENT_LIB} STATIC ${_FIPS_CURRENT_SOURCES})
    set(_FIPS_CURRENT_LIB "")
    set(_FIPS_CURRENT_SOURCES "")
endmacro()

macro(fips_dir dir)
    set(_FIPS_CURRENT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/${dir}")
endmacro()

macro(fips_files)
    foreach(file ${ARGN})
        if(NOT file STREQUAL "GROUP" AND NOT file MATCHES "^\\.")
            list(APPEND _FIPS_CURRENT_SOURCES "${_FIPS_CURRENT_DIR}/${file}")
        endif()
    endforeach()
endmacro()

function(fips_src dir)
    set(options NO_RECURSE)
    set(oneValueArgs GROUP)
    set(multiValueArgs EXCEPT)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    set(src_dir "${CMAKE_CURRENT_SOURCE_DIR}/${dir}")
    if(ARG_NO_RECURSE)
        file(GLOB sources "${src_dir}/*.c" "${src_dir}/*.cc" "${src_dir}/*.cpp")
    else()
        file(GLOB_RECURSE sources "${src_dir}/*.c" "${src_dir}/*.cc" "${src_dir}/*.cpp")
    endif()

    # Filter out EXCEPT patterns
    if(ARG_EXCEPT)
        foreach(pattern ${ARG_EXCEPT})
            list(FILTER sources EXCLUDE REGEX "${pattern}")
        endforeach()
    endif()

    set(_FIPS_CURRENT_SOURCES ${_FIPS_CURRENT_SOURCES} ${sources} PARENT_SCOPE)
endfunction()

macro(fips_deps)
    target_link_libraries(${_FIPS_CURRENT_LIB} ${ARGN})
endmacro()

macro(fips_begin_app name type)
    set(_FIPS_CURRENT_LIB ${name})
    set(_FIPS_CURRENT_SOURCES "")
endmacro()

macro(fips_end_app)
    add_executable(${_FIPS_CURRENT_LIB} ${_FIPS_CURRENT_SOURCES})
    set(_FIPS_CURRENT_LIB "")
    set(_FIPS_CURRENT_SOURCES "")
endmacro()
