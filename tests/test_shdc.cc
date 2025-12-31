// Test sokol-shdc library
#include "shdc/spirv.h"
#include "shdc/args.h"
#include "shdc/input.h"
#include "shdc/spirvcross.h"
#include "shdc/reflection.h"
#include "shdc/generators/generate.h"
#include <cstdio>

using namespace shdc;
using namespace shdc::refl;
using namespace shdc::gen;

int main(int argc, const char** argv) {
    if (argc < 2) {
        printf("Usage: test_shdc <shader.glsl>\n");
        return 1;
    }

    Spirv::initialize_spirv_tools();

    // Parse args (minimal)
    const Args args = Args::parse(argc, argv);
    if (!args.valid) {
        printf("Invalid args\n");
        return args.exit_code;
    }

    // Load and parse input
    Input inp = Input::load_and_parse(args.input, args.module);
    if (inp.out_error.valid()) {
        inp.out_error.print(args.error_format);
        return 10;
    }

    printf("Loaded shader: %s\n", args.input.c_str());
    printf("Programs found: %zu\n", inp.programs.size());
    for (const auto& [name, prog] : inp.programs) {
        printf("  - %s (vs: %s, fs: %s)\n", name.c_str(), prog.vs_name.c_str(), prog.fs_name.c_str());
    }

    // Compile to SPIRV for HLSL5
    Slang::Enum slang = Slang::HLSL5;
    Spirv spirv = Spirv::compile_glsl_and_extract_bindings(inp, slang, args.defines);
    if (!spirv.errors.empty()) {
        for (const ErrMsg& err : spirv.errors) {
            err.print(args.error_format);
            if (err.type == ErrMsg::ERROR) {
                return 10;
            }
        }
    }

    // Cross-compile to HLSL
    Spirvcross spirvcross = Spirvcross::translate(inp, spirv, slang);
    if (spirvcross.error.valid()) {
        spirvcross.error.print(args.error_format);
        return 10;
    }

    printf("Compilation successful!\n");
    printf("Generated sources:\n");
    for (const auto& src : spirvcross.sources) {
        if (src.valid) {
            printf("--- Snippet %d ---\n%s\n", src.snippet_index, src.source_code.c_str());
        }
    }

    Spirv::finalize_spirv_tools();
    return 0;
}
