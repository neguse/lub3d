add_executable(newexample WIN32
    main.c
    sokol_impl.c
    ${PROJECT_SOURCE_DIR}/Generator/sokol_app.c
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

# Working directory for Visual Studio debugger
if(WIN32)
    set_target_properties(newexample PROPERTIES
        VS_DEBUGGER_WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}/newexample")
endif()
