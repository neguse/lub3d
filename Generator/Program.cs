using Generator.ClangAst;
using Generator.Modules;

if (args.Length < 2)
{
    Console.WriteLine("Usage: Generator <input.json> <output-dir>");
    return 1;
}

var input = args[0];
var outputDir = args[1];

Directory.CreateDirectory(outputDir);

var reg = TypeRegistry.Load(input);

var cPath = Path.Combine(outputDir, $"sokol_{reg.ModuleName}.c");
File.WriteAllText(cPath, App.GenerateC(reg));
Console.WriteLine($"Generated: {cPath}");

var luaPath = Path.Combine(outputDir, $"{reg.ModuleName}.lua");
File.WriteAllText(luaPath, App.GenerateLua(reg));
Console.WriteLine($"Generated: {luaPath}");

return 0;
