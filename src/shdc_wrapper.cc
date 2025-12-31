// C wrapper for sokol-shdc library
#include "shdc_wrapper.h"
#include "shdc/spirv.h"
#include "shdc/input.h"
#include "shdc/spirvcross.h"
#include "shdc/bytecode.h"
#include "shdc/reflection.h"
#include "shdc/types/slang.h"

#include <cstring>
#include <cstdlib>
#include <fstream>
#include <string>

using namespace shdc;

extern "C" {

void shdc_init(void) {
    Spirv::initialize_spirv_tools();
}

void shdc_shutdown(void) {
    Spirv::finalize_spirv_tools();
}

static Slang::Enum parse_slang(const char* slang_str) {
    if (strcmp(slang_str, "glsl410") == 0) return Slang::GLSL410;
    if (strcmp(slang_str, "glsl430") == 0) return Slang::GLSL430;
    if (strcmp(slang_str, "glsl300es") == 0) return Slang::GLSL300ES;
    if (strcmp(slang_str, "glsl310es") == 0) return Slang::GLSL310ES;
    if (strcmp(slang_str, "hlsl4") == 0) return Slang::HLSL4;
    if (strcmp(slang_str, "hlsl5") == 0) return Slang::HLSL5;
    if (strcmp(slang_str, "metal_macos") == 0) return Slang::METAL_MACOS;
    if (strcmp(slang_str, "metal_ios") == 0) return Slang::METAL_IOS;
    if (strcmp(slang_str, "metal_sim") == 0) return Slang::METAL_SIM;
    if (strcmp(slang_str, "wgsl") == 0) return Slang::WGSL;
    return Slang::Num; // Invalid
}

// Helper to duplicate string with malloc
static char* dup_str(const std::string& s) {
    if (s.empty()) return nullptr;
    char* p = (char*)malloc(s.size() + 1);
    if (p) {
        memcpy(p, s.c_str(), s.size() + 1);
    }
    return p;
}

// Helper to duplicate binary data with malloc
static char* dup_bin(const void* data, size_t len) {
    if (!data || len == 0) return nullptr;
    char* p = (char*)malloc(len);
    if (p) {
        memcpy(p, data, len);
    }
    return p;
}

static shdc_compile_result_t make_error(const std::string& msg) {
    shdc_compile_result_t result = {};
    result.error_msg = dup_str(msg);
    return result;
}

shdc_compile_result_t shdc_compile(const char* source, const char* program_name, const char* slang_str) {
    shdc_compile_result_t result = {};

    // Parse slang
    Slang::Enum slang = parse_slang(slang_str);
    if (slang == Slang::Num) {
        return make_error("Invalid shader language: " + std::string(slang_str));
    }

    // Write source to temp file (Input::load_and_parse requires file path)
    std::string tmp_path;
#ifdef _WIN32
    char* tmp_env = getenv("TEMP");
    if (!tmp_env) tmp_env = getenv("TMP");
    tmp_path = tmp_env ? tmp_env : ".";
    tmp_path += "\\shdc_temp_";
#else
    tmp_path = "/tmp/shdc_temp_";
#endif
    tmp_path += std::to_string(reinterpret_cast<uintptr_t>(source));
    tmp_path += ".glsl";

    {
        std::ofstream f(tmp_path);
        if (!f) {
            return make_error("Failed to create temp file");
        }
        f << source;
    }

    // Load and parse
    Input inp = Input::load_and_parse(tmp_path, "");
    std::remove(tmp_path.c_str());

    if (inp.out_error.valid()) {
        return make_error(inp.out_error.msg);
    }

    // Find program
    auto prog_it = inp.programs.find(program_name);
    if (prog_it == inp.programs.end()) {
        return make_error("Program not found: " + std::string(program_name));
    }
    const Program& prog = prog_it->second;

    // Compile to SPIRV
    std::vector<std::string> defines;
    Spirv spirv = Spirv::compile_glsl_and_extract_bindings(inp, slang, defines);
    if (!spirv.errors.empty()) {
        for (const ErrMsg& err : spirv.errors) {
            if (err.type == ErrMsg::ERROR) {
                return make_error(err.msg);
            }
        }
    }

    // Cross-compile
    Spirvcross spirvcross = Spirvcross::translate(inp, spirv, slang);
    if (spirvcross.error.valid()) {
        return make_error(spirvcross.error.msg);
    }

    // Find VS and FS snippets
    int vs_idx = inp.snippet_map.count(prog.vs_name) ? inp.snippet_map.at(prog.vs_name) : -1;
    int fs_idx = inp.snippet_map.count(prog.fs_name) ? inp.snippet_map.at(prog.fs_name) : -1;

    if (vs_idx < 0 || fs_idx < 0) {
        return make_error("VS or FS snippet not found");
    }

    // Get sources
    const SpirvcrossSource* vs_src = spirvcross.find_source_by_snippet_index(vs_idx);
    const SpirvcrossSource* fs_src = spirvcross.find_source_by_snippet_index(fs_idx);

    if (!vs_src || !vs_src->valid) {
        return make_error("VS compilation failed");
    }
    if (!fs_src || !fs_src->valid) {
        return make_error("FS compilation failed");
    }

    // Allocate result strings
    result.vs_source = dup_str(vs_src->source_code);
    result.vs_source_len = static_cast<int>(vs_src->source_code.size());
    result.fs_source = dup_str(fs_src->source_code);
    result.fs_source_len = static_cast<int>(fs_src->source_code.size());

    // For HLSL, we need to compile to bytecode
    if (Slang::is_hlsl(slang)) {
        // Build args for bytecode compilation
        Args args;
        args.byte_code = true;
        args.slang = Slang::bit(slang);

        Bytecode bytecode = Bytecode::compile(args, inp, spirvcross, slang);
        if (!bytecode.errors.empty()) {
            for (const ErrMsg& err : bytecode.errors) {
                if (err.type == ErrMsg::ERROR) {
                    // Free already allocated
                    free((void*)result.vs_source);
                    free((void*)result.fs_source);
                    return make_error(err.msg);
                }
            }
        }

        // Get bytecode
        const BytecodeBlob* vs_blob = bytecode.find_blob_by_snippet_index(vs_idx);
        const BytecodeBlob* fs_blob = bytecode.find_blob_by_snippet_index(fs_idx);

        if (vs_blob && vs_blob->valid) {
            result.vs_bytecode = dup_bin(vs_blob->data.data(), vs_blob->data.size());
            result.vs_bytecode_len = static_cast<int>(vs_blob->data.size());
        }
        if (fs_blob && fs_blob->valid) {
            result.fs_bytecode = dup_bin(fs_blob->data.data(), fs_blob->data.size());
            result.fs_bytecode_len = static_cast<int>(fs_blob->data.size());
        }
    }

    result.success = 1;
    return result;
}

void shdc_free_result(shdc_compile_result_t* result) {
    if (!result) return;
    free((void*)result->error_msg);
    free((void*)result->vs_source);
    free((void*)result->fs_source);
    free((void*)result->vs_bytecode);
    free((void*)result->fs_bytecode);
    *result = {};
}

} // extern "C"
