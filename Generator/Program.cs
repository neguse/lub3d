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

    IModule[] modules = [new App()];

    var jsonOptions = new JsonSerializerOptions
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    foreach (var mod in modules)
    {
        var headerPath = Path.Combine(depsDir, mod.Header);
        var includePaths = mod.IncludeDirs.Select(d => Path.Combine(depsDir, d)).ToList();
        Console.WriteLine($"Parsing {headerPath} ...");

        var astModule = ClangRunner.ParseHeader(
            clangPath, headerPath, mod.ModuleName,
            mod.Prefix, [.. mod.DepPrefixes], includePaths);

        var reg = TypeRegistry.FromModule(astModule);
        var moduleId = mod.ModuleName.Replace('.', '_');

        var jsonPath = Path.Combine(outputDir, $"{moduleId}.json");
        File.WriteAllText(jsonPath, JsonSerializer.Serialize(astModule, jsonOptions));
        Console.WriteLine($"Generated: {jsonPath}");

        var cPath = Path.Combine(outputDir, $"{moduleId}.c");
        File.WriteAllText(cPath, mod.GenerateC(reg));
        Console.WriteLine($"Generated: {cPath}");

        var luaPath = Path.Combine(outputDir, $"{moduleId}.lua");
        File.WriteAllText(luaPath, mod.GenerateLua(reg));
        Console.WriteLine($"Generated: {luaPath}");
    }

    return 0;
});

return rootCommand.Parse(args).Invoke();

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
