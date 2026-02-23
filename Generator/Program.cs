using System.CommandLine;
using System.Text.Json;
using System.Text.Json.Serialization;
using Generator;
using Generator.ClangAst;
using Generator.Modules.Sokol;
using Generator.Modules.Miniaudio;
using Generator.Modules.Imgui;
using Generator.Modules.Stb;
using Generator.Modules.Box2d;
using Generator.Modules.Jolt;

var outputDirArg = new Argument<DirectoryInfo>("output-dir")
{
    Description = "Output directory for generated files",
};

var depsOption = new Option<DirectoryInfo?>("--deps")
{
    Description = "Path to deps directory (default: auto-detect)",
};

var clangOption = new Option<FileInfo?>("--clang")
{
    Description = "Path to clang executable (default: auto-detect from PATH or CLANG env)",
};

var rootCommand = new RootCommand("Generate Lua bindings from C headers");
rootCommand.Arguments.Add(outputDirArg);
rootCommand.Options.Add(depsOption);
rootCommand.Options.Add(clangOption);

rootCommand.SetAction(parseResult =>
{
    var outputDir = parseResult.GetValue(outputDirArg)!.FullName;
    var depsDir = parseResult.GetValue(depsOption)?.FullName ?? FindDepsDir();
    var clangPath = parseResult.GetValue(clangOption)?.FullName ?? FindClang();
    if (depsDir == null)
    {
        Console.Error.WriteLine("Error: deps directory not found. Use --deps or place deps/ relative to Generator.");
        return 1;
    }
    if (clangPath == null)
    {
        Console.Error.WriteLine("Error: clang not found. Use --clang or add clang to PATH.");
        return 1;
    }

    Directory.CreateDirectory(outputDir);

    var allMetrics = new List<ModuleMetrics>();
    var allUnbound = new List<(UnboundReport Unhandled, SkipReport? Skipped)>();

    // --- ヘッダグループ (Sokol) ---
    var sokolHeaders = new List<string>
    {
        "sokol_log.h", "sokol_gfx.h", "sokol_app.h", "sokol_time.h",
        "sokol_audio.h", "sokol_gl.h", "sokol_debugtext.h",
        "sokol_shape.h", "sokol_glue.h", "sokol_imgui.h"
    };
    var sokolIncludePaths = new List<string>
    {
        Path.Combine(depsDir, "sokol"),
        Path.Combine(depsDir, "sokol", "util")
    };

    // --- モジュール定義 ---
    IModule[] modules = [
        new App(), new Audio(), new DebugText(), new Gfx(),
        new Gl(), new Glue(), new Imgui(), new Log(), new Shape(), new Time()
    ];

    var prefixToModule = modules.ToDictionary(m => m.Prefix, m => m.ModuleName);

    // --- Clang 1回実行 ---
    var headerPaths = sokolHeaders.Select(h => FindHeader(h, sokolIncludePaths)).ToList();
    Console.WriteLine($"Parsing {headerPaths.Count} headers with clang ...");

    var (sokolRawJson, unified) = ClangRunner.ParseHeadersWithRawJson(
        clangPath, headerPaths,
        prefixToModule.Keys.ToList(),
        sokolIncludePaths);

    // clang 生 AST JSON を保存
    var sokolAstPath = Path.Combine(outputDir, "sokol_clang_ast.json");
    File.WriteAllText(sokolAstPath, sokolRawJson);
    Console.WriteLine($"Generated: {sokolAstPath} (raw clang AST)");

    Console.WriteLine($"  Found {unified.Decls.Count} declarations total");

    var jsonOptions = new JsonSerializerOptions
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    // --- 各モジュール生成 ---
    foreach (var mod in modules)
    {
        var view = ClangRunner.CreateView(unified, mod.Prefix, mod.ModuleName);
        var reg = TypeRegistry.FromModule(view);

        // SourceLink: find the header that corresponds to this module
        var moduleSuffix = mod.ModuleName.Split('.').Last();
        var headerFile = sokolHeaders.FirstOrDefault(h =>
            h.Equals($"sokol_{moduleSuffix}.h", StringComparison.OrdinalIgnoreCase));
        SourceLink? sourceLink = null;
        if (headerFile != null)
        {
            var fullPath = FindHeader(headerFile, sokolIncludePaths);
            var isUtil = fullPath.Replace('\\', '/').Contains("/util/");
            var relPath = isUtil
                ? $"sokol/util/{headerFile}"
                : $"sokol/{headerFile}";
            sourceLink = SourceLink.FromHeader(depsDir, relPath);
        }

        var moduleId = mod.ModuleName.Replace('.', '_');

        var jsonPath = Path.Combine(outputDir, $"{moduleId}.json");
        File.WriteAllText(jsonPath, JsonSerializer.Serialize(view, jsonOptions));
        Console.WriteLine($"Generated: {jsonPath}");

        var cPath = Path.Combine(outputDir, $"{moduleId}.c");
        File.WriteAllText(cPath, mod.GenerateC(reg, prefixToModule));
        Console.WriteLine($"Generated: {cPath}");

        var luaPath = LuaOutputPath(outputDir, mod.ModuleName);
        File.WriteAllText(luaPath, mod.GenerateLua(reg, prefixToModule, sourceLink));
        Console.WriteLine($"Generated: {luaPath}");

        var spec = mod.BuildSpec(reg, prefixToModule, sourceLink);
        var skip = mod.CollectSkips(reg);
        allMetrics.Add(ModuleMetrics.Collect(mod.ModuleName, reg, spec, skip));
        allUnbound.Add(ModuleMetrics.CollectUnbound(mod.ModuleName, reg, spec, skip));
    }

    // --- ヘッダグループ (Miniaudio) ---
    var miniaudioModule = new MiniaudioModule();
    var miniaudioHeader = Path.Combine(depsDir, "miniaudio", "miniaudio.h");
    var miniaudioIncludePaths = new List<string>
    {
        Path.Combine(depsDir, "miniaudio")
    };

    Console.WriteLine("Parsing miniaudio header with clang ...");
    var (maRawJson, maUnified) = ClangRunner.ParseHeadersWithRawJson(
        clangPath, [miniaudioHeader], [miniaudioModule.Prefix],
        miniaudioIncludePaths);

    // clang 生 AST JSON を保存
    var maAstPath = Path.Combine(outputDir, "miniaudio_clang_ast.json");
    File.WriteAllText(maAstPath, maRawJson);
    Console.WriteLine($"Generated: {maAstPath} (raw clang AST)");

    Console.WriteLine($"  Found {maUnified.Decls.Count} declarations total");

    {
        var maView = ClangRunner.CreateView(maUnified, miniaudioModule.Prefix, miniaudioModule.ModuleName);
        var maReg = TypeRegistry.FromModule(maView);
        var maPrefixToModule = new Dictionary<string, string> { [miniaudioModule.Prefix] = miniaudioModule.ModuleName };
        var maSourceLink = SourceLink.FromHeader(depsDir, "miniaudio/miniaudio.h");

        var maModuleId = miniaudioModule.ModuleName.Replace('.', '_');

        var maJsonPath = Path.Combine(outputDir, $"{maModuleId}.json");
        File.WriteAllText(maJsonPath, JsonSerializer.Serialize(maView, jsonOptions));
        Console.WriteLine($"Generated: {maJsonPath}");

        var maCPath = Path.Combine(outputDir, $"{maModuleId}.c");
        File.WriteAllText(maCPath, miniaudioModule.GenerateC(maReg, maPrefixToModule));
        Console.WriteLine($"Generated: {maCPath}");

        var maLuaPath = LuaOutputPath(outputDir, miniaudioModule.ModuleName);
        File.WriteAllText(maLuaPath, miniaudioModule.GenerateLua(maReg, maPrefixToModule, maSourceLink));
        Console.WriteLine($"Generated: {maLuaPath}");

        var maSpec = miniaudioModule.BuildSpec(maReg, maPrefixToModule, maSourceLink);
        var maSkip = ((IModule)miniaudioModule).CollectSkips(maReg);
        allMetrics.Add(ModuleMetrics.Collect(miniaudioModule.ModuleName, maReg, maSpec, maSkip));
        allUnbound.Add(ModuleMetrics.CollectUnbound(miniaudioModule.ModuleName, maReg, maSpec, maSkip));
    }

    // --- ヘッダグループ (Dear ImGui) ---
    var imguiHeaderPath = Path.Combine(depsDir, "imgui", "imgui.h");
    if (File.Exists(imguiHeaderPath))
    {
        var imguiModule = new ImguiModule();
        var imguiIncludePaths = new List<string>
        {
            Path.Combine(depsDir, "imgui")
        };

        Console.WriteLine("Parsing imgui header with clang++ ...");
        var (imguiRawJson, imguiParsed) = ClangRunner.ParseCppHeadersWithRawJson(
            clangPath, [imguiHeaderPath], ["ImGui"],
            imguiIncludePaths,
            ["IMGUI_DISABLE_OBSOLETE_FUNCTIONS"]);

        var imguiAstPath = Path.Combine(outputDir, "imgui_clang_ast.json");
        File.WriteAllText(imguiAstPath, imguiRawJson);
        Console.WriteLine($"Generated: {imguiAstPath} (raw clang++ AST)");

        var imguiFuncCount = imguiParsed.Decls.OfType<Funcs>().Count();
        var imguiEnumCount = imguiParsed.Decls.OfType<Enums>().Count();
        Console.WriteLine($"  Found {imguiFuncCount} functions, {imguiEnumCount} enums");

        var imguiReg = TypeRegistry.FromModule(imguiParsed);
        var imguiPrefixToModule = new Dictionary<string, string>();

        var imguiCppPath = Path.Combine(outputDir, "imgui_gen.cpp");
        File.WriteAllText(imguiCppPath, imguiModule.GenerateC(imguiReg, imguiPrefixToModule));
        Console.WriteLine($"Generated: {imguiCppPath}");

        var imguiSourceLink = SourceLink.FromHeader(depsDir, "imgui/imgui.h");
        var imguiLuaPath = LuaOutputPath(outputDir, imguiModule.ModuleName);
        File.WriteAllText(imguiLuaPath, imguiModule.GenerateLua(imguiReg, imguiPrefixToModule, imguiSourceLink));
        Console.WriteLine($"Generated: {imguiLuaPath}");

        var imguiSpec = imguiModule.BuildSpec(imguiReg, imguiPrefixToModule, imguiSourceLink);
        var imguiSkip = ((IModule)imguiModule).CollectSkips(imguiReg);
        allMetrics.Add(ModuleMetrics.Collect(imguiModule.ModuleName, imguiReg, imguiSpec, imguiSkip));
        allUnbound.Add(ModuleMetrics.CollectUnbound(imguiModule.ModuleName, imguiReg, imguiSpec, imguiSkip));
    }
    else
    {
        Console.WriteLine("Skipping Dear ImGui (deps/imgui/imgui.h not found)");
    }

    // --- ヘッダグループ (stb_image) ---
    {
        var stbImageModule = new StbImageModule();
        var stbHeader = Path.Combine(depsDir, "stb", "stb_image.h");
        var stbIncludePaths = new List<string> { Path.Combine(depsDir, "stb") };

        Console.WriteLine("Parsing stb_image header with clang ...");
        var (stbRawJson, stbUnified) = ClangRunner.ParseHeadersWithRawJson(
            clangPath, [stbHeader], [stbImageModule.Prefix], stbIncludePaths);

        var stbAstPath = Path.Combine(outputDir, "stb_image_clang_ast.json");
        File.WriteAllText(stbAstPath, stbRawJson);
        Console.WriteLine($"Generated: {stbAstPath} (raw clang AST)");
        Console.WriteLine($"  Found {stbUnified.Decls.Count} declarations total");

        var stbView = ClangRunner.CreateView(stbUnified, stbImageModule.Prefix, stbImageModule.ModuleName);
        var stbReg = TypeRegistry.FromModule(stbView);
        var stbPrefixToModule = new Dictionary<string, string> { [stbImageModule.Prefix] = stbImageModule.ModuleName };
        var stbSourceLink = SourceLink.FromHeader(depsDir, "stb/stb_image.h");

        var stbModuleId = stbImageModule.ModuleName.Replace('.', '_');

        var stbJsonPath = Path.Combine(outputDir, $"{stbModuleId}.json");
        File.WriteAllText(stbJsonPath, JsonSerializer.Serialize(stbView, jsonOptions));
        Console.WriteLine($"Generated: {stbJsonPath}");

        var stbCPath = Path.Combine(outputDir, $"{stbModuleId}.c");
        File.WriteAllText(stbCPath, stbImageModule.GenerateC(stbReg, stbPrefixToModule));
        Console.WriteLine($"Generated: {stbCPath}");

        var stbLuaPath = LuaOutputPath(outputDir, stbImageModule.ModuleName);
        File.WriteAllText(stbLuaPath, stbImageModule.GenerateLua(stbReg, stbPrefixToModule, stbSourceLink));
        Console.WriteLine($"Generated: {stbLuaPath}");

        var stbSpec = stbImageModule.BuildSpec(stbReg, stbPrefixToModule, stbSourceLink);
        var stbSkip = ((IModule)stbImageModule).CollectSkips(stbReg);
        allMetrics.Add(ModuleMetrics.Collect(stbImageModule.ModuleName, stbReg, stbSpec, stbSkip));
        allUnbound.Add(ModuleMetrics.CollectUnbound(stbImageModule.ModuleName, stbReg, stbSpec, stbSkip));
    }

    // --- ヘッダグループ (Box2D) ---
    var box2dHeaderPath = Path.Combine(depsDir, "box2d", "include", "box2d", "box2d.h");
    if (File.Exists(box2dHeaderPath))
    {
        var box2dModule = new Box2dModule();
        var box2dHeaders = new List<string>
        {
            Path.Combine(depsDir, "box2d", "include", "box2d", "box2d.h"),
            Path.Combine(depsDir, "box2d", "include", "box2d", "types.h"),
            Path.Combine(depsDir, "box2d", "include", "box2d", "math_functions.h"),
            Path.Combine(depsDir, "box2d", "include", "box2d", "collision.h"),
            Path.Combine(depsDir, "box2d", "include", "box2d", "id.h"),
            Path.Combine(depsDir, "box2d", "include", "box2d", "base.h"),
        };
        var box2dIncludePaths = new List<string>
        {
            Path.Combine(depsDir, "box2d", "include")
        };

        Console.WriteLine("Parsing Box2D headers with clang ...");
        var (b2RawJson, b2Unified) = ClangRunner.ParseHeadersWithRawJson(
            clangPath, box2dHeaders, [box2dModule.Prefix],
            box2dIncludePaths);

        var b2AstPath = Path.Combine(outputDir, "box2d_clang_ast.json");
        File.WriteAllText(b2AstPath, b2RawJson);
        Console.WriteLine($"Generated: {b2AstPath} (raw clang AST)");
        Console.WriteLine($"  Found {b2Unified.Decls.Count} declarations total");

        var b2View = ClangRunner.CreateView(b2Unified, box2dModule.Prefix, box2dModule.ModuleName);
        var b2Reg = TypeRegistry.FromModule(b2View);
        var b2PrefixToModule = new Dictionary<string, string> { [box2dModule.Prefix] = box2dModule.ModuleName };
        var b2SourceLink = SourceLink.FromHeader(depsDir, "box2d/include/box2d/box2d.h");

        var b2ModuleId = box2dModule.ModuleName.Replace('.', '_');

        var b2JsonPath = Path.Combine(outputDir, $"{b2ModuleId}.json");
        File.WriteAllText(b2JsonPath, JsonSerializer.Serialize(b2View, jsonOptions));
        Console.WriteLine($"Generated: {b2JsonPath}");

        var b2CPath = Path.Combine(outputDir, $"{b2ModuleId}.c");
        File.WriteAllText(b2CPath, box2dModule.GenerateC(b2Reg, b2PrefixToModule));
        Console.WriteLine($"Generated: {b2CPath}");

        var b2LuaPath = LuaOutputPath(outputDir, box2dModule.ModuleName);
        File.WriteAllText(b2LuaPath, box2dModule.GenerateLua(b2Reg, b2PrefixToModule, b2SourceLink));
        Console.WriteLine($"Generated: {b2LuaPath}");

        var b2Spec = box2dModule.BuildSpec(b2Reg, b2PrefixToModule, b2SourceLink);
        var b2Skip = ((IModule)box2dModule).CollectSkips(b2Reg);
        allMetrics.Add(ModuleMetrics.Collect(box2dModule.ModuleName, b2Reg, b2Spec, b2Skip));
        allUnbound.Add(ModuleMetrics.CollectUnbound(box2dModule.ModuleName, b2Reg, b2Spec, b2Skip));
    }
    else
    {
        Console.WriteLine("Skipping Box2D (deps/box2d/include/box2d/box2d.h not found)");
    }

    // --- Jolt Physics (LuaCATS only — C++ binding is hand-written) ---
    {
        var joltModule = new JoltModule();
        var joltEmptyModule = new Generator.ClangAst.Module(joltModule.ModuleName, joltModule.Prefix, [], []);
        var joltReg = TypeRegistry.FromModule(joltEmptyModule);
        var joltPrefixToModule = new Dictionary<string, string> { [joltModule.Prefix] = joltModule.ModuleName };

        var joltLuaPath = LuaOutputPath(outputDir, joltModule.ModuleName);
        File.WriteAllText(joltLuaPath, joltModule.GenerateLua(joltReg, joltPrefixToModule));
        Console.WriteLine($"Generated: {joltLuaPath}");

        var joltSpec = joltModule.BuildSpec(joltReg, joltPrefixToModule);
        var joltSkip = ((IModule)joltModule).CollectSkips(joltReg);
        allMetrics.Add(ModuleMetrics.Collect(joltModule.ModuleName, joltReg, joltSpec, joltSkip));
        allUnbound.Add(ModuleMetrics.CollectUnbound(joltModule.ModuleName, joltReg, joltSpec, joltSkip));
    }

    ModuleMetrics.PrintTable(allMetrics);
    ModuleMetrics.PrintUnbound(allUnbound);

    return 0;
});

return rootCommand.Parse(args).Invoke();

/// <summary>
/// モジュール名から LuaCATS .lua ファイルパスを生成 (dots → /)
/// 例: "sokol.app" → "sokol/app.lua", "miniaudio" → "miniaudio.lua"
/// </summary>
static string LuaOutputPath(string outputDir, string moduleName)
{
    var relativePath = moduleName.Replace('.', Path.DirectorySeparatorChar) + ".lua";
    var fullPath = Path.Combine(outputDir, relativePath);
    var dir = Path.GetDirectoryName(fullPath);
    if (dir != null) Directory.CreateDirectory(dir);
    return fullPath;
}

static string FindHeader(string headerName, List<string> includePaths)
{
    foreach (var dir in includePaths)
    {
        var path = Path.Combine(dir, headerName);
        if (File.Exists(path)) return path;
    }
    throw new FileNotFoundException($"Header not found: {headerName} in {string.Join(", ", includePaths)}");
}

static string? FindClang()
{
    var env = Environment.GetEnvironmentVariable("CLANG");
    if (env != null && File.Exists(env)) return env;

    var pathDirs = (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator);
    foreach (var dir in pathDirs)
    {
        var candidate = Path.Combine(dir, OperatingSystem.IsWindows() ? "clang.exe" : "clang");
        if (File.Exists(candidate)) return candidate;
    }
    return null;
}

static string? FindDepsDir()
{
    var generatorDir = AppContext.BaseDirectory;
    var dir = new DirectoryInfo(generatorDir);
    while (dir != null)
    {
        var candidate = Path.Combine(dir.FullName, "deps");
        if (Directory.Exists(candidate)) return candidate;
        dir = dir.Parent;
    }
    return null;
}
