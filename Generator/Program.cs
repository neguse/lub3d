using System.CommandLine;
using System.Text.Json;
using System.Text.Json.Serialization;
using Generator;
using Generator.ClangAst;
using Generator.Modules.Sokol;

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

    // --- ヘッダグループ (Sokol) ---
    var sokolHeaders = new List<string>
    {
        "sokol_log.h", "sokol_gfx.h", "sokol_app.h", "sokol_time.h",
        "sokol_audio.h", "sokol_gl.h", "sokol_debugtext.h",
        "sokol_shape.h", "sokol_glue.h"
    };
    var sokolIncludePaths = new List<string>
    {
        Path.Combine(depsDir, "sokol"),
        Path.Combine(depsDir, "sokol", "util")
    };

    // --- モジュール定義 ---
    IModule[] modules = [
        new App(), new Audio(), new DebugText(), new Gfx(),
        new Gl(), new Glue(), new Log(), new Shape(), new Time()
    ];

    var prefixToModule = modules.ToDictionary(m => m.Prefix, m => m.ModuleName);

    // --- Clang 1回実行 ---
    var headerPaths = sokolHeaders.Select(h => FindHeader(h, sokolIncludePaths)).ToList();
    Console.WriteLine($"Parsing {headerPaths.Count} headers with clang ...");

    var unified = ClangRunner.ParseHeaders(
        clangPath, headerPaths,
        prefixToModule.Keys.ToList(),
        sokolIncludePaths);

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

        // SourceLink: find the header that corresponds to this module's prefix
        var headerFile = sokolHeaders.FirstOrDefault(h =>
        {
            var fullPath = FindHeader(h, sokolIncludePaths);
            return fullPath != null;
        });
        SourceLink? sourceLink = null;
        if (headerFile != null)
        {
            var relPath = headerFile.Contains("util")
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

        var luaPath = Path.Combine(outputDir, $"{moduleId}.lua");
        File.WriteAllText(luaPath, mod.GenerateLua(reg, prefixToModule, sourceLink));
        Console.WriteLine($"Generated: {luaPath}");
    }

    return 0;
});

return rootCommand.Parse(args).Invoke();

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
