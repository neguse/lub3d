cmake_minimum_required(VERSION 3.20)
project(mane3d C CXX)

# MSVC parallel compilation and UTF-8 source encoding
if(MSVC)
    add_compile_options(/MP /utf-8)
endif()

# Options
option(MANE3D_BUILD_SHARED "Build as shared library" OFF)
option(MANE3D_BUILD_SHDC "Build sokol-shdc library" ON)
option(MANE3D_BUILD_IMGUI "Build Dear ImGui integration" ON)
option(MANE3D_USE_SYSTEM_LUA "Use system Lua instead of bundled" OFF)
option(MANE3D_BACKEND_GL "Use OpenGL backend" OFF)
option(MANE3D_BACKEND_GLES3 "Use OpenGL ES3 backend" OFF)
option(MANE3D_BACKEND_D3D11 "Use Direct3D 11 backend" OFF)
option(MANE3D_BACKEND_METAL "Use Metal backend" OFF)
option(MANE3D_BACKEND_WGPU "Use WebGPU backend" OFF)

# Lua 5.5
if(MANE3D_USE_SYSTEM_LUA)
    find_package(Lua REQUIRED)
    set(LUA_TARGET ${LUA_LIBRARIES})
    set(LUA_INCLUDE ${LUA_INCLUDE_DIR})
else()
    # Bundled Lua 5.5
    set(LUA_SRC
        deps/lua/lapi.c
        deps/lua/lcode.c
        deps/lua/lctype.c
        deps/lua/ldebug.c
        deps/lua/ldo.c
        deps/lua/ldump.c
        deps/lua/lfunc.c
        deps/lua/lgc.c
        deps/lua/llex.c
        deps/lua/lmem.c
        deps/lua/lobject.c
        deps/lua/lopcodes.c
        deps/lua/lparser.c
        deps/lua/lstate.c
        deps/lua/lstring.c
        deps/lua/ltable.c
        deps/lua/ltm.c
        deps/lua/lundump.c
        deps/lua/lvm.c
        deps/lua/lzio.c
        deps/lua/lauxlib.c
        deps/lua/lbaselib.c
        deps/lua/lcorolib.c
        deps/lua/ldblib.c
        deps/lua/liolib.c
        deps/lua/lmathlib.c
        deps/lua/loadlib.c
        deps/lua/loslib.c
        deps/lua/lstrlib.c
        deps/lua/ltablib.c
        deps/lua/lutf8lib.c
        deps/lua/linit.c
    )
    add_library(lua55 STATIC ${LUA_SRC})
    target_include_directories(lua55 PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/deps/lua)
    if(EMSCRIPTEN)
        target_compile_definitions(lua55 PRIVATE LUA_USE_POSIX)
    elseif(UNIX AND NOT APPLE)
        target_compile_definitions(lua55 PRIVATE LUA_USE_LINUX)
        target_link_libraries(lua55 PUBLIC dl m)
    elseif(APPLE)
        target_compile_definitions(lua55 PRIVATE LUA_USE_MACOSX)
    endif()
    set(LUA_TARGET lua55)
    set(LUA_INCLUDE ${CMAKE_CURRENT_SOURCE_DIR}/deps/lua)
endif()

# Code generation
find_package(Python3 COMPONENTS Interpreter)
set(SOKOL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/deps/sokol" CACHE PATH "Path to sokol directory")
set(BINDGEN_DIR "${SOKOL_DIR}/bindgen" CACHE PATH "Path to sokol/bindgen directory")

set(MANE3D_GENERATED
    ${CMAKE_CURRENT_SOURCE_DIR}/gen/bindings/sokol_log.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gen/bindings/sokol_gfx.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gen/bindings/sokol_app.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gen/bindings/sokol_glue.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gen/bindings/sokol_time.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gen/bindings/sokol_audio.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gen/bindings/sokol_gl.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gen/bindings/sokol_debugtext.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gen/bindings/sokol_shape.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gen/licenses.c
)

if(Python3_FOUND)
    add_custom_command(
        OUTPUT ${CMAKE_CURRENT_SOURCE_DIR}/gen/bindings/sokol_log.c
               ${CMAKE_CURRENT_SOURCE_DIR}/gen/bindings/sokol_gfx.c
               ${CMAKE_CURRENT_SOURCE_DIR}/gen/bindings/sokol_app.c
               ${CMAKE_CURRENT_SOURCE_DIR}/gen/bindings/sokol_glue.c
               ${CMAKE_CURRENT_SOURCE_DIR}/gen/bindings/sokol_time.c
               ${CMAKE_CURRENT_SOURCE_DIR}/gen/bindings/sokol_audio.c
               ${CMAKE_CURRENT_SOURCE_DIR}/gen/bindings/sokol_gl.c
               ${CMAKE_CURRENT_SOURCE_DIR}/gen/bindings/sokol_debugtext.c
               ${CMAKE_CURRENT_SOURCE_DIR}/gen/bindings/sokol_shape.c
        COMMAND ${CMAKE_COMMAND} -E env PYTHONUTF8=1
            ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/scripts/gen_lua.py
            --sokol ${SOKOL_DIR}
            --bindgen ${BINDGEN_DIR}
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
        DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/scripts/gen_lua.py
        COMMENT "Generating Lua bindings..."
    )

    add_custom_command(
        OUTPUT ${CMAKE_CURRENT_SOURCE_DIR}/gen/licenses.c
        COMMAND ${CMAKE_COMMAND} -E env PYTHONUTF8=1
            ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/scripts/gen_licenses.py
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
        DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/scripts/gen_licenses.py
        COMMENT "Generating license data..."
    )
endif()

# mane3d sources
set(MANE3D_SOURCES
    src/sokol_impl.c
    src/stb_image_lua.c
    ${MANE3D_GENERATED}
)

# Library type
if(MANE3D_BUILD_SHARED)
    add_library(mane3d SHARED ${MANE3D_SOURCES})
    target_compile_definitions(mane3d PRIVATE MANE3D_EXPORTS)
else()
    add_library(mane3d STATIC ${MANE3D_SOURCES})
    # For static builds, define MANE3D_API as empty
    target_compile_definitions(mane3d PUBLIC MANE3D_API=)
endif()

# Include directories
target_include_directories(mane3d
    PUBLIC ${LUA_INCLUDE}
    PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/deps/sokol
    PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/deps/sokol/util
    PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/deps/stb
)

# Link Lua
target_link_libraries(mane3d PUBLIC ${LUA_TARGET})

# Backend selection for sokol_impl.c
if(MANE3D_BACKEND_GL)
    target_compile_definitions(mane3d PRIVATE SOKOL_GLCORE)
elseif(MANE3D_BACKEND_GLES3)
    target_compile_definitions(mane3d PRIVATE SOKOL_GLES3)
elseif(MANE3D_BACKEND_D3D11)
    target_compile_definitions(mane3d PRIVATE SOKOL_D3D11)
elseif(MANE3D_BACKEND_METAL)
    target_compile_definitions(mane3d PRIVATE SOKOL_METAL)
elseif(MANE3D_BACKEND_WGPU)
    target_compile_definitions(mane3d PRIVATE SOKOL_WGPU)
else()
    # Auto-detect based on platform
    if(EMSCRIPTEN)
        target_compile_definitions(mane3d PRIVATE SOKOL_WGPU)
    elseif(WIN32)
        target_compile_definitions(mane3d PRIVATE SOKOL_D3D11)
    elseif(APPLE)
        target_compile_definitions(mane3d PRIVATE SOKOL_METAL)
        set_target_properties(mane3d PROPERTIES
            COMPILE_FLAGS "-x objective-c"
        )
    else()
        target_compile_definitions(mane3d PRIVATE SOKOL_GLCORE)
    endif()
endif()

# Platform-specific libraries
if(EMSCRIPTEN)
    # WebGPU via emdawnwebgpu port
    target_compile_options(mane3d PRIVATE --use-port=emdawnwebgpu)
    target_link_options(mane3d PUBLIC --use-port=emdawnwebgpu)
elseif(WIN32)
    target_link_libraries(mane3d PUBLIC
        kernel32
        user32
        gdi32
        ole32
    )
    if(MANE3D_BACKEND_D3D11 OR NOT (MANE3D_BACKEND_GL OR MANE3D_BACKEND_GLES3 OR MANE3D_BACKEND_METAL OR MANE3D_BACKEND_WGPU))
        target_link_libraries(mane3d PUBLIC d3d11 dxgi)
    endif()
elseif(APPLE)
    find_library(COCOA_LIBRARY Cocoa REQUIRED)
    find_library(QUARTZCORE_LIBRARY QuartzCore REQUIRED)
    find_library(METAL_LIBRARY Metal REQUIRED)
    find_library(METALKIT_LIBRARY MetalKit REQUIRED)
    find_library(AUDIOTOOLBOX_LIBRARY AudioToolbox REQUIRED)
    target_link_libraries(mane3d PUBLIC
        ${COCOA_LIBRARY}
        ${QUARTZCORE_LIBRARY}
        ${METAL_LIBRARY}
        ${METALKIT_LIBRARY}
        ${AUDIOTOOLBOX_LIBRARY}
    )
elseif(UNIX)
    find_package(Threads REQUIRED)
    find_package(X11 REQUIRED)
    find_package(OpenGL REQUIRED)
    target_link_libraries(mane3d PUBLIC
        Threads::Threads
        ${X11_LIBRARIES}
        ${X11_Xi_LIB}
        ${X11_Xcursor_LIB}
        ${OPENGL_LIBRARIES}
        dl
        m
        asound
    )
endif()

# Lua interpreter (optional)
option(MANE3D_BUILD_INTERPRETER "Build Lua interpreter" OFF)
if(MANE3D_BUILD_INTERPRETER AND NOT MANE3D_USE_SYSTEM_LUA)
    add_executable(lua deps/lua/lua.c)
    target_link_libraries(lua lua55)
    if(UNIX AND NOT EMSCRIPTEN)
        target_link_libraries(lua readline)
    endif()
endif()

# Example
option(MANE3D_BUILD_EXAMPLE "Build example" ON)
if(MANE3D_BUILD_EXAMPLE)
    if(EMSCRIPTEN)
        add_executable(mane3d-example examples/main.c)
    else()
        add_executable(mane3d-example WIN32 examples/main.c)
    endif()
    target_include_directories(mane3d-example PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/deps/sokol
        ${CMAKE_CURRENT_SOURCE_DIR}/deps/sokol/util
        ${LUA_INCLUDE}
    )
    target_link_libraries(mane3d-example mane3d)

    # SHDC support
    if(MANE3D_BUILD_SHDC)
        target_compile_definitions(mane3d-example PRIVATE MANE3D_HAS_SHDC)
    endif()

    # Backend defines for example
    if(MANE3D_BACKEND_GL)
        target_compile_definitions(mane3d-example PRIVATE SOKOL_GLCORE)
    elseif(MANE3D_BACKEND_GLES3)
        target_compile_definitions(mane3d-example PRIVATE SOKOL_GLES3)
    elseif(MANE3D_BACKEND_D3D11)
        target_compile_definitions(mane3d-example PRIVATE SOKOL_D3D11)
    elseif(MANE3D_BACKEND_METAL)
        target_compile_definitions(mane3d-example PRIVATE SOKOL_METAL)
    elseif(MANE3D_BACKEND_WGPU)
        target_compile_definitions(mane3d-example PRIVATE SOKOL_WGPU)
    else()
        # Auto-detect
        if(EMSCRIPTEN)
            target_compile_definitions(mane3d-example PRIVATE SOKOL_WGPU)
        elseif(WIN32)
            target_compile_definitions(mane3d-example PRIVATE SOKOL_D3D11)
        elseif(APPLE)
            target_compile_definitions(mane3d-example PRIVATE SOKOL_METAL)
        else()
            target_compile_definitions(mane3d-example PRIVATE SOKOL_GLCORE)
        endif()
    endif()

    # Set working directory for Visual Studio debugger
    if(WIN32)
        set_target_properties(mane3d-example PROPERTIES
            VS_DEBUGGER_WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
    endif()

    # Emscripten-specific settings
    if(EMSCRIPTEN)
        set_target_properties(mane3d-example PROPERTIES
            SUFFIX ".html"
        )
        target_link_options(mane3d-example PRIVATE
            -sASYNCIFY
            -sALLOW_MEMORY_GROWTH=1
            -sASSERTIONS=1
            -sSTACK_SIZE=1048576
        )
    endif()
endif()

# Install
install(TARGETS mane3d
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
)
install(DIRECTORY deps/sokol/ DESTINATION include/sokol FILES_MATCHING PATTERN "*.h")
install(DIRECTORY deps/sokol/util/ DESTINATION include/sokol FILES_MATCHING PATTERN "*.h")
install(DIRECTORY deps/lua/ DESTINATION include/lua FILES_MATCHING PATTERN "*.h")

# Dear ImGui integration (optional)
if(MANE3D_BUILD_IMGUI)
    # ImGui auto-generated bindings (requires clang++)
    option(MANE3D_GEN_IMGUI "Generate ImGui bindings (requires clang++)" ON)
    if(MANE3D_GEN_IMGUI AND Python3_FOUND)
        find_program(CLANGPP_EXECUTABLE NAMES clang++ clang++.exe clang++-18 clang++-17 clang++-16 clang++-15
            HINTS "C:/Program Files/LLVM/bin" "C:/Program Files (x86)/LLVM/bin"
        )
        message(STATUS "CLANGPP_EXECUTABLE: ${CLANGPP_EXECUTABLE}")
        if(CLANGPP_EXECUTABLE)
            add_custom_command(
                OUTPUT ${CMAKE_CURRENT_SOURCE_DIR}/gen/bindings/imgui_gen.cpp
                COMMAND ${CMAKE_COMMAND} -E env PYTHONUTF8=1
                    ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/scripts/gen_imgui.py
                    ${CMAKE_CURRENT_SOURCE_DIR}/deps/imgui/imgui.h
                    ${CMAKE_CURRENT_SOURCE_DIR}/gen/bindings/imgui_gen.cpp
                WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
                DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/scripts/gen_imgui.py
                        ${CMAKE_CURRENT_SOURCE_DIR}/scripts/gen_ir_imgui.py
                        ${CMAKE_CURRENT_SOURCE_DIR}/scripts/gen_util_imgui.py
                        ${CMAKE_CURRENT_SOURCE_DIR}/deps/imgui/imgui.h
                COMMENT "Generating ImGui Lua bindings..."
            )
            set(IMGUI_GEN_SOURCE ${CMAKE_CURRENT_SOURCE_DIR}/gen/bindings/imgui_gen.cpp)
        else()
            message(WARNING "clang++ not found, skipping ImGui binding generation")
        endif()
    endif()

    # ImGui library (C++)
    add_library(imgui_lib STATIC
        src/imgui_impl.cpp
        src/imgui_sokol.cpp
        ${IMGUI_GEN_SOURCE}
    )
    target_include_directories(imgui_lib
        PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/deps/imgui
        PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/deps/sokol
        PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/deps/sokol/util
        PRIVATE ${LUA_INCLUDE}
    )
    target_link_libraries(imgui_lib PUBLIC ${LUA_TARGET})

    # Backend defines for ImGui
    if(MANE3D_BACKEND_GL)
        target_compile_definitions(imgui_lib PRIVATE SOKOL_GLCORE)
    elseif(MANE3D_BACKEND_GLES3)
        target_compile_definitions(imgui_lib PRIVATE SOKOL_GLES3)
    elseif(MANE3D_BACKEND_D3D11)
        target_compile_definitions(imgui_lib PRIVATE SOKOL_D3D11)
    elseif(MANE3D_BACKEND_METAL)
        target_compile_definitions(imgui_lib PRIVATE SOKOL_METAL)
    elseif(MANE3D_BACKEND_WGPU)
        target_compile_definitions(imgui_lib PRIVATE SOKOL_WGPU)
    else()
        if(EMSCRIPTEN)
            target_compile_definitions(imgui_lib PRIVATE SOKOL_WGPU)
        elseif(WIN32)
            target_compile_definitions(imgui_lib PRIVATE SOKOL_D3D11)
        elseif(APPLE)
            target_compile_definitions(imgui_lib PRIVATE SOKOL_METAL)
        else()
            target_compile_definitions(imgui_lib PRIVATE SOKOL_GLCORE)
        endif()
    endif()

    # Link ImGui to mane3d
    target_link_libraries(mane3d PUBLIC imgui_lib)
    target_compile_definitions(mane3d PUBLIC MANE3D_HAS_IMGUI)

    # Add define if using auto-generated bindings
    if(IMGUI_GEN_SOURCE)
        target_compile_definitions(imgui_lib PRIVATE MANE3D_GEN_IMGUI)
    endif()
endif()

# BC7 encoder library (optional)
option(MANE3D_BUILD_BC7ENC "Build BC7 encoder library" ON)
if(MANE3D_BUILD_BC7ENC)
    set(BC7ENC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/deps/bc7enc_rdo)

    add_library(bc7enc_lib STATIC
        ${BC7ENC_DIR}/bc7enc.cpp
        ${BC7ENC_DIR}/bc7decomp.cpp
        ${BC7ENC_DIR}/bc7decomp_ref.cpp
        ${BC7ENC_DIR}/ert.cpp
        ${BC7ENC_DIR}/rdo_bc_encoder.cpp
        ${BC7ENC_DIR}/rgbcx.cpp
        ${BC7ENC_DIR}/utils.cpp
        ${BC7ENC_DIR}/lodepng.cpp
    )
    target_include_directories(bc7enc_lib PUBLIC ${BC7ENC_DIR})
    set_target_properties(bc7enc_lib PROPERTIES CXX_STANDARD 11)

    # Enable OpenMP for parallel encoding
    find_package(OpenMP)
    if(OpenMP_CXX_FOUND)
        target_link_libraries(bc7enc_lib PUBLIC OpenMP::OpenMP_CXX)
    endif()

    # Suppress warnings in third-party code
    if(MSVC)
        target_compile_options(bc7enc_lib PRIVATE /W0)
    else()
        target_compile_options(bc7enc_lib PRIVATE -w)
    endif()

    # Add Lua bindings
    target_sources(mane3d PRIVATE src/bc7enc_lua.cpp)
    target_compile_definitions(mane3d PUBLIC MANE3D_HAS_BC7ENC)
    target_link_libraries(mane3d PUBLIC bc7enc_lib)
endif()

# sokol-shdc library (optional)
if(MANE3D_BUILD_SHDC)
    include(cmake/sokol-shdc.cmake)

    # Wrapper library (C++20)
    add_library(shdc_wrapper STATIC src/shdc_wrapper.cc)
    target_include_directories(shdc_wrapper PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/deps/sokol-tools/src
        ${CMAKE_CURRENT_SOURCE_DIR}/src
    )
    target_link_libraries(shdc_wrapper sokol_shdc_lib)
    set_target_properties(shdc_wrapper PROPERTIES CXX_STANDARD 20)

    # Add Lua bindings and link wrapper
    target_sources(mane3d PRIVATE src/shdc_lua.c)
    target_include_directories(mane3d PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    target_compile_definitions(mane3d PRIVATE MANE3D_HAS_SHDC)
    target_link_libraries(mane3d PUBLIC shdc_wrapper)

endif()
