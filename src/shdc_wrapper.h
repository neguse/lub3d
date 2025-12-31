#ifndef SHDC_WRAPPER_H
#define SHDC_WRAPPER_H

#ifdef __cplusplus
extern "C" {
#endif

// Initialize sokol-shdc (call once at startup)
void shdc_init(void);

// Shutdown sokol-shdc (call once at cleanup)
void shdc_shutdown(void);

// Compile result structure
typedef struct {
    int success;
    const char* error_msg;
    const char* vs_source;
    int vs_source_len;
    const char* fs_source;
    int fs_source_len;
    const char* vs_bytecode;
    int vs_bytecode_len;
    const char* fs_bytecode;
    int fs_bytecode_len;
} shdc_compile_result_t;

// Compile shader
// source: GLSL source with @vs/@fs/@program tags
// program_name: name of @program to compile
// slang: target language ("hlsl5", "metal_macos", "glsl430", "glsl300es", "wgsl")
// Returns compile result. Call shdc_free_result when done.
shdc_compile_result_t shdc_compile(const char* source, const char* program_name, const char* slang);

// Free compile result resources
void shdc_free_result(shdc_compile_result_t* result);

#ifdef __cplusplus
}
#endif

#endif // SHDC_WRAPPER_H
