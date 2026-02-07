cmake_minimum_required(VERSION 3.20)
project(lub3d C CXX)

# Auto-detect sccache (use if available)
find_program(CCACHE_PROGRAM sccache)
if(CCACHE_PROGRAM)
    message(STATUS "Using compiler cache: ${CCACHE_PROGRAM}")
    set(CMAKE_C_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
    set(CMAKE_CXX_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
endif()

# MSVC parallel compilation and UTF-8 source encoding
if(MSVC)
    add_compile_options(/MP /utf-8)
    # Use /Z7 instead of /Zi to embed debug info in object files (required for ccache)
    if(CCACHE_PROGRAM)
        string(REPLACE "/Zi" "/Z7" CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG}")
        string(REPLACE "/Zi" "/Z7" CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG}")
        string(REPLACE "/Zi" "/Z7" CMAKE_C_FLAGS_RELWITHDEBINFO "${CMAKE_C_FLAGS_RELWITHDEBINFO}")
        string(REPLACE "/Zi" "/Z7" CMAKE_CXX_FLAGS_RELWITHDEBINFO "${CMAKE_CXX_FLAGS_RELWITHDEBINFO}")
    endif()
endif()

# Options
option(LUB3D_BUILD_SHARED "Build as shared library" OFF)
option(LUB3D_BUILD_SHDC "Build sokol-shdc library" ON)
option(LUB3D_BUILD_IMGUI "Build Dear ImGui integration" ON)
option(LUB3D_USE_SYSTEM_LUA "Use system Lua instead of bundled" OFF)
option(LUB3D_BACKEND_GL "Use OpenGL backend" OFF)
option(LUB3D_BACKEND_GLES3 "Use OpenGL ES3 backend" OFF)
option(LUB3D_BACKEND_D3D11 "Use Direct3D 11 backend" OFF)
option(LUB3D_BACKEND_METAL "Use Metal backend" OFF)
option(LUB3D_BACKEND_WGPU "Use WebGPU backend" OFF)
option(LUB3D_BACKEND_DUMMY "Use Dummy backend for headless testing" OFF)
option(LUB3D_BUILD_TESTS "Build test runner" OFF)

# Lua 5.5
if(LUB3D_USE_SYSTEM_LUA)
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
find_program(CLANGPP_EXECUTABLE NAMES clang++ clang++.exe clang++-18 clang++-17 clang++-16 clang++-15
    HINTS "C:/Program Files/LLVM/bin" "C:/Program Files (x86)/LLVM/bin" "$ENV{EMSDK}/upstream/bin"
)
message(STATUS "CLANGPP_EXECUTABLE: ${CLANGPP_EXECUTABLE}")
set(SOKOL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/deps/sokol" CACHE PATH "Path to sokol directory")
set(BINDGEN_DIR "${SOKOL_DIR}/bindgen" CACHE PATH "Path to sokol/bindgen directory")

set(LUB3D_GENERATED
    ${CMAKE_CURRENT_SOURCE_DIR}/gen/sokol_log.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gen/sokol_gfx.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gen/sokol_app.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gen/sokol_glue.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gen/sokol_time.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gen/sokol_audio.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gen/sokol_gl.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gen/sokol_debugtext.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gen/sokol_shape.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gen/miniaudio.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gen/licenses.c
)

# C# Generator for all Sokol modules
set(GENERATOR_DIR "${CMAKE_CURRENT_SOURCE_DIR}/Generator")
set(GEN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/gen")
find_program(DOTNET_EXECUTABLE dotnet REQUIRED)
find_program(CLANG_EXECUTABLE NAMES clang clang.exe
    HINTS "${CLANGPP_EXECUTABLE}/.."
    REQUIRED)

add_custom_command(
    OUTPUT ${GEN_DIR}/sokol_app.c ${GEN_DIR}/sokol_app.lua
           ${GEN_DIR}/sokol_log.c ${GEN_DIR}/sokol_log.lua
           ${GEN_DIR}/sokol_time.c ${GEN_DIR}/sokol_time.lua
           ${GEN_DIR}/sokol_gfx.c ${GEN_DIR}/sokol_gfx.lua
           ${GEN_DIR}/sokol_glue.c ${GEN_DIR}/sokol_glue.lua
           ${GEN_DIR}/sokol_audio.c ${GEN_DIR}/sokol_audio.lua
           ${GEN_DIR}/sokol_gl.c ${GEN_DIR}/sokol_gl.lua
           ${GEN_DIR}/sokol_debugtext.c ${GEN_DIR}/sokol_debugtext.lua
           ${GEN_DIR}/sokol_shape.c ${GEN_DIR}/sokol_shape.lua
           ${GEN_DIR}/sokol_imgui.c ${GEN_DIR}/sokol_imgui.lua
           ${GEN_DIR}/miniaudio.c ${GEN_DIR}/miniaudio.lua
           ${GEN_DIR}/imgui_gen.cpp ${GEN_DIR}/imgui.lua
    COMMAND ${DOTNET_EXECUTABLE} run --project ${GENERATOR_DIR} --
        ${GEN_DIR}
        --deps ${CMAKE_CURRENT_SOURCE_DIR}/deps
        --clang ${CLANG_EXECUTABLE}
    DEPENDS
        ${CMAKE_CURRENT_SOURCE_DIR}/deps/sokol/sokol_app.h
        ${CMAKE_CURRENT_SOURCE_DIR}/deps/sokol/sokol_log.h
        ${CMAKE_CURRENT_SOURCE_DIR}/deps/sokol/sokol_time.h
        ${CMAKE_CURRENT_SOURCE_DIR}/deps/sokol/sokol_gfx.h
        ${CMAKE_CURRENT_SOURCE_DIR}/deps/sokol/sokol_audio.h
        ${CMAKE_CURRENT_SOURCE_DIR}/deps/sokol/util/sokol_gl.h
        ${CMAKE_CURRENT_SOURCE_DIR}/deps/sokol/util/sokol_debugtext.h
        ${CMAKE_CURRENT_SOURCE_DIR}/deps/sokol/util/sokol_shape.h
        ${CMAKE_CURRENT_SOURCE_DIR}/deps/sokol/sokol_glue.h
        ${CMAKE_CURRENT_SOURCE_DIR}/deps/sokol/util/sokol_imgui.h
        ${CMAKE_CURRENT_SOURCE_DIR}/deps/miniaudio/miniaudio.h
        ${CMAKE_CURRENT_SOURCE_DIR}/deps/imgui/imgui.h
        ${GENERATOR_DIR}/Program.cs
        ${GENERATOR_DIR}/IModule.cs
        ${GENERATOR_DIR}/ModuleSpec.cs
        ${GENERATOR_DIR}/BindingType.cs
        ${GENERATOR_DIR}/Pipeline.cs
        ${GENERATOR_DIR}/ClangAst/ClangAst.cs
        ${GENERATOR_DIR}/ClangAst/TypeRegistry.cs
        ${GENERATOR_DIR}/CBinding/CBinding.cs
        ${GENERATOR_DIR}/CBinding/CBindingGen.cs
        ${GENERATOR_DIR}/LuaCats/LuaCats.cs
        ${GENERATOR_DIR}/LuaCats/LuaCatsGen.cs
        ${GENERATOR_DIR}/Modules/Sokol/SokolModule.cs
        ${GENERATOR_DIR}/Modules/Sokol/App.cs
        ${GENERATOR_DIR}/Modules/Sokol/Audio.cs
        ${GENERATOR_DIR}/Modules/Sokol/DebugText.cs
        ${GENERATOR_DIR}/Modules/Sokol/Gfx.cs
        ${GENERATOR_DIR}/Modules/Sokol/Gl.cs
        ${GENERATOR_DIR}/Modules/Sokol/Glue.cs
        ${GENERATOR_DIR}/Modules/Sokol/Log.cs
        ${GENERATOR_DIR}/Modules/Sokol/Shape.cs
        ${GENERATOR_DIR}/Modules/Sokol/Time.cs
        ${GENERATOR_DIR}/Modules/Sokol/Imgui.cs
        ${GENERATOR_DIR}/Modules/Miniaudio/MiniaudioModule.cs
        ${GENERATOR_DIR}/Modules/Imgui/ImguiModule.cs
    COMMENT "Running Generator (header -> bindings)"
)

# License generator (Python)
if(Python3_FOUND)
    add_custom_command(
        OUTPUT ${CMAKE_CURRENT_SOURCE_DIR}/gen/licenses.c
        COMMAND ${CMAKE_COMMAND} -E env PYTHONUTF8=1
            ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/scripts/gen_licenses.py
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
        DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/scripts/gen_licenses.py
        COMMENT "Generating license data..."
    )
endif()

# lub3d sources
set(LUB3D_SOURCES
    src/sokol_impl.c
    src/miniaudio_impl.c
    src/stb_image_lua.c
    src/lub3d_lua.c
    ${LUB3D_GENERATED}
)

# Library type
if(LUB3D_BUILD_SHARED)
    add_library(lub3d SHARED ${LUB3D_SOURCES})
    target_compile_definitions(lub3d PRIVATE LUB3D_EXPORTS)
else()
    add_library(lub3d STATIC ${LUB3D_SOURCES})
    # For static builds, define LUB3D_API as empty
    target_compile_definitions(lub3d PUBLIC LUB3D_API=)
endif()

# Include directories
target_include_directories(lub3d
    PUBLIC ${LUA_INCLUDE}
    PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/deps/sokol
    PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/deps/sokol/util
    PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/deps/stb
    PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/deps/miniaudio
)

# Link Lua
target_link_libraries(lub3d PUBLIC ${LUA_TARGET})

# Backend selection for sokol_impl.c
if(LUB3D_BACKEND_DUMMY)
    target_compile_definitions(lub3d PRIVATE SOKOL_DUMMY_BACKEND)
elseif(LUB3D_BACKEND_GL)
    target_compile_definitions(lub3d PRIVATE SOKOL_GLCORE)
elseif(LUB3D_BACKEND_GLES3)
    target_compile_definitions(lub3d PRIVATE SOKOL_GLES3)
elseif(LUB3D_BACKEND_D3D11)
    target_compile_definitions(lub3d PRIVATE SOKOL_D3D11)
elseif(LUB3D_BACKEND_METAL)
    target_compile_definitions(lub3d PRIVATE SOKOL_METAL)
elseif(LUB3D_BACKEND_WGPU)
    target_compile_definitions(lub3d PRIVATE SOKOL_WGPU)
else()
    # Auto-detect based on platform
    if(EMSCRIPTEN)
        target_compile_definitions(lub3d PRIVATE SOKOL_WGPU)
    elseif(WIN32)
        target_compile_definitions(lub3d PRIVATE SOKOL_D3D11)
    elseif(APPLE)
        target_compile_definitions(lub3d PRIVATE SOKOL_METAL)
        set_target_properties(lub3d PROPERTIES
            COMPILE_FLAGS "-x objective-c"
        )
    else()
        target_compile_definitions(lub3d PRIVATE SOKOL_GLCORE)
    endif()
endif()

# Platform-specific libraries (skip for DUMMY backend)
if(NOT LUB3D_BACKEND_DUMMY)
if(EMSCRIPTEN)
    # WebGPU via emdawnwebgpu port
    target_compile_options(lub3d PRIVATE --use-port=emdawnwebgpu)
    target_link_options(lub3d PUBLIC --use-port=emdawnwebgpu)
elseif(WIN32)
    target_link_libraries(lub3d PUBLIC
        kernel32
        user32
        gdi32
        ole32
    )
    if(LUB3D_BACKEND_D3D11 OR NOT (LUB3D_BACKEND_GL OR LUB3D_BACKEND_GLES3 OR LUB3D_BACKEND_METAL OR LUB3D_BACKEND_WGPU))
        target_link_libraries(lub3d PUBLIC d3d11 dxgi)
    endif()
elseif(APPLE)
    find_library(COCOA_LIBRARY Cocoa REQUIRED)
    find_library(QUARTZCORE_LIBRARY QuartzCore REQUIRED)
    find_library(METAL_LIBRARY Metal REQUIRED)
    find_library(METALKIT_LIBRARY MetalKit REQUIRED)
    find_library(AUDIOTOOLBOX_LIBRARY AudioToolbox REQUIRED)
    target_link_libraries(lub3d PUBLIC
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
    target_link_libraries(lub3d PUBLIC
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
endif()

# Lua interpreter (optional)
option(LUB3D_BUILD_INTERPRETER "Build Lua interpreter" OFF)
if(LUB3D_BUILD_INTERPRETER AND NOT LUB3D_USE_SYSTEM_LUA)
    add_executable(lua deps/lua/lua.c)
    target_link_libraries(lua lua55)
    if(UNIX AND NOT EMSCRIPTEN)
        target_link_libraries(lua readline)
    endif()
endif()

# Example
option(LUB3D_BUILD_EXAMPLE "Build example" ON)
if(LUB3D_BUILD_EXAMPLE)
    if(EMSCRIPTEN)
        add_executable(lub3d-example examples/main.c)
    else()
        add_executable(lub3d-example WIN32 examples/main.c)
    endif()
    target_include_directories(lub3d-example PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/deps/sokol
        ${CMAKE_CURRENT_SOURCE_DIR}/deps/sokol/util
        ${CMAKE_CURRENT_SOURCE_DIR}/src
        ${LUA_INCLUDE}
    )
    target_link_libraries(lub3d-example lub3d)

    # SHDC support
    if(LUB3D_BUILD_SHDC)
        target_compile_definitions(lub3d-example PRIVATE LUB3D_HAS_SHDC)
    endif()

    # Backend defines for example
    if(LUB3D_BACKEND_DUMMY)
        target_compile_definitions(lub3d-example PRIVATE SOKOL_DUMMY_BACKEND)
    elseif(LUB3D_BACKEND_GL)
        target_compile_definitions(lub3d-example PRIVATE SOKOL_GLCORE)
    elseif(LUB3D_BACKEND_GLES3)
        target_compile_definitions(lub3d-example PRIVATE SOKOL_GLES3)
    elseif(LUB3D_BACKEND_D3D11)
        target_compile_definitions(lub3d-example PRIVATE SOKOL_D3D11)
    elseif(LUB3D_BACKEND_METAL)
        target_compile_definitions(lub3d-example PRIVATE SOKOL_METAL)
    elseif(LUB3D_BACKEND_WGPU)
        target_compile_definitions(lub3d-example PRIVATE SOKOL_WGPU)
    else()
        # Auto-detect
        if(EMSCRIPTEN)
            target_compile_definitions(lub3d-example PRIVATE SOKOL_WGPU)
        elseif(WIN32)
            target_compile_definitions(lub3d-example PRIVATE SOKOL_D3D11)
        elseif(APPLE)
            target_compile_definitions(lub3d-example PRIVATE SOKOL_METAL)
        else()
            target_compile_definitions(lub3d-example PRIVATE SOKOL_GLCORE)
        endif()
    endif()

    # Set working directory for Visual Studio debugger
    if(WIN32)
        set_target_properties(lub3d-example PROPERTIES
            VS_DEBUGGER_WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
    endif()

    # Emscripten-specific settings
    if(EMSCRIPTEN)
        set_target_properties(lub3d-example PROPERTIES
            SUFFIX ".html"
        )
        target_link_options(lub3d-example PRIVATE
            # -sASYNCIFY  # disabled for faster builds
            -sALLOW_MEMORY_GROWTH=1
            -sASSERTIONS=1
            -sSTACK_SIZE=1048576
        )
    endif()
endif()

# Install
install(TARGETS lub3d
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
)
install(DIRECTORY deps/sokol/ DESTINATION include/sokol FILES_MATCHING PATTERN "*.h")
install(DIRECTORY deps/sokol/util/ DESTINATION include/sokol FILES_MATCHING PATTERN "*.h")
install(DIRECTORY deps/lua/ DESTINATION include/lua FILES_MATCHING PATTERN "*.h")

# Dear ImGui integration (optional)
if(LUB3D_BUILD_IMGUI)
    # ImGui auto-generated bindings (C# Generator output)
    set(IMGUI_GEN_SOURCE ${GEN_DIR}/imgui_gen.cpp)

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
    if(LUB3D_BACKEND_DUMMY)
        target_compile_definitions(imgui_lib PRIVATE SOKOL_DUMMY_BACKEND)
    elseif(LUB3D_BACKEND_GL)
        target_compile_definitions(imgui_lib PRIVATE SOKOL_GLCORE)
    elseif(LUB3D_BACKEND_GLES3)
        target_compile_definitions(imgui_lib PRIVATE SOKOL_GLES3)
    elseif(LUB3D_BACKEND_D3D11)
        target_compile_definitions(imgui_lib PRIVATE SOKOL_D3D11)
    elseif(LUB3D_BACKEND_METAL)
        target_compile_definitions(imgui_lib PRIVATE SOKOL_METAL)
    elseif(LUB3D_BACKEND_WGPU)
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

    # Stub sokol_app functions for dummy backend (sokol_app.h has no dummy support)
    if(LUB3D_BACKEND_DUMMY)
        target_sources(imgui_lib PRIVATE src/sapp_stub.c)
    endif()

    # Link ImGui to lub3d
    target_sources(lub3d PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/gen/sokol_imgui.c)
    target_link_libraries(lub3d PUBLIC imgui_lib)
    target_compile_definitions(lub3d PUBLIC LUB3D_HAS_IMGUI)

    # Add define if using auto-generated bindings
    if(IMGUI_GEN_SOURCE)
        target_compile_definitions(imgui_lib PRIVATE LUB3D_GEN_IMGUI)
    endif()
endif()

# BC7 encoder library (optional)
option(LUB3D_BUILD_BC7ENC "Build BC7 encoder library" ON)
if(LUB3D_BUILD_BC7ENC)
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
        # -w suppresses warnings, -include adds missing stdint.h for clang
        target_compile_options(bc7enc_lib PRIVATE -w -include cstdint)
    endif()

    # Add Lua bindings
    target_sources(lub3d PRIVATE src/bc7enc_lua.cpp)
    target_compile_definitions(lub3d PUBLIC LUB3D_HAS_BC7ENC)
    target_link_libraries(lub3d PUBLIC bc7enc_lib)
endif()

# sokol-shdc library (optional)
if(LUB3D_BUILD_SHDC)
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
    target_sources(lub3d PRIVATE src/shdc_lua.c)
    target_include_directories(lub3d PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    target_compile_definitions(lub3d PRIVATE LUB3D_HAS_SHDC)
    target_link_libraries(lub3d PUBLIC shdc_wrapper)

endif()

# Test runner (headless)
if(LUB3D_BUILD_TESTS)
    add_executable(lub3d-test tests/test_runner.c)
    target_include_directories(lub3d-test PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/deps/sokol
        ${CMAKE_CURRENT_SOURCE_DIR}/deps/sokol/util
        ${CMAKE_CURRENT_SOURCE_DIR}/src
        ${LUA_INCLUDE}
    )
    target_link_libraries(lub3d-test lub3d)

    # Backend defines for test runner
    if(LUB3D_BACKEND_DUMMY)
        target_compile_definitions(lub3d-test PRIVATE SOKOL_DUMMY_BACKEND)
    elseif(LUB3D_BACKEND_GL)
        target_compile_definitions(lub3d-test PRIVATE SOKOL_GLCORE)
    elseif(LUB3D_BACKEND_GLES3)
        target_compile_definitions(lub3d-test PRIVATE SOKOL_GLES3)
    elseif(LUB3D_BACKEND_D3D11)
        target_compile_definitions(lub3d-test PRIVATE SOKOL_D3D11)
    elseif(LUB3D_BACKEND_METAL)
        target_compile_definitions(lub3d-test PRIVATE SOKOL_METAL)
    elseif(LUB3D_BACKEND_WGPU)
        target_compile_definitions(lub3d-test PRIVATE SOKOL_WGPU)
    else()
        if(EMSCRIPTEN)
            target_compile_definitions(lub3d-test PRIVATE SOKOL_WGPU)
        elseif(WIN32)
            target_compile_definitions(lub3d-test PRIVATE SOKOL_D3D11)
        elseif(APPLE)
            target_compile_definitions(lub3d-test PRIVATE SOKOL_METAL)
        else()
            target_compile_definitions(lub3d-test PRIVATE SOKOL_GLCORE)
        endif()
    endif()

    if(LUB3D_BUILD_SHDC)
        target_compile_definitions(lub3d-test PRIVATE LUB3D_HAS_SHDC)
    endif()
endif()
