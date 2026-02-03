set(GENERATOR_DIR "${PROJECT_SOURCE_DIR}/Generator")
set(GEN_DIR "${PROJECT_SOURCE_DIR}/newgen")
set(GENERATOR_OUTPUT_C "${GEN_DIR}/sokol_app.c")
set(GENERATOR_OUTPUT_LUA "${GEN_DIR}/sokol_app.lua")

find_program(DOTNET_EXECUTABLE dotnet REQUIRED)
find_program(CLANG_EXECUTABLE NAMES clang clang.exe
    HINTS "${CLANGPP_EXECUTABLE}/.."
    REQUIRED)

add_custom_command(
    OUTPUT ${GENERATOR_OUTPUT_C} ${GENERATOR_OUTPUT_LUA}
    COMMAND ${DOTNET_EXECUTABLE} run --project ${GENERATOR_DIR} --
        ${GEN_DIR}
        --deps ${PROJECT_SOURCE_DIR}/deps
        --clang ${CLANG_EXECUTABLE}
    DEPENDS
        ${PROJECT_SOURCE_DIR}/deps/sokol/sokol_app.h
        ${GENERATOR_DIR}/Program.cs
        ${GENERATOR_DIR}/IModule.cs
        ${GENERATOR_DIR}/Pipeline.cs
        ${GENERATOR_DIR}/ClangAst/ClangAst.cs
        ${GENERATOR_DIR}/ClangAst/TypeRegistry.cs
        ${GENERATOR_DIR}/CBinding/CBinding.cs
        ${GENERATOR_DIR}/CBinding/CBindingGen.cs
        ${GENERATOR_DIR}/LuaCats/LuaCats.cs
        ${GENERATOR_DIR}/LuaCats/LuaCatsGen.cs
        ${GENERATOR_DIR}/Modules/Sokol/App.cs
    COMMENT "Running Generator (header -> bindings)"
)

add_executable(newexample WIN32
    main.c
    sokol_impl.c
    ${GENERATOR_OUTPUT_C}
)

target_include_directories(newexample PRIVATE
    ${PROJECT_SOURCE_DIR}/deps/sokol
    ${PROJECT_SOURCE_DIR}/deps/sokol/util
    ${LUA_INCLUDE}
)

target_compile_definitions(newexample PRIVATE MANE3D_API=)
target_link_libraries(newexample PRIVATE ${LUA_TARGET})

# Backend selection (same logic as parent)
if(MANE3D_BACKEND_D3D11 OR (WIN32 AND NOT (MANE3D_BACKEND_GL OR MANE3D_BACKEND_GLES3 OR MANE3D_BACKEND_METAL OR MANE3D_BACKEND_WGPU OR MANE3D_BACKEND_DUMMY)))
    target_compile_definitions(newexample PRIVATE SOKOL_D3D11)
    target_link_libraries(newexample PRIVATE kernel32 user32 gdi32 ole32 d3d11 dxgi)
elseif(MANE3D_BACKEND_GL OR (UNIX AND NOT APPLE))
    target_compile_definitions(newexample PRIVATE SOKOL_GLCORE)
elseif(MANE3D_BACKEND_METAL OR APPLE)
    target_compile_definitions(newexample PRIVATE SOKOL_METAL)
endif()
