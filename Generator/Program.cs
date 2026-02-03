using Generator.ClangAst;
using Generator.Modules.Sokol;

if (args.Length < 2)
{
    Console.WriteLine("Usage: Generator <input.json> <output-dir>");
    return 1;
}

var input = args[0];
var outputDir = args[1];

Directory.CreateDirectory(outputDir);

var reg = TypeRegistry.Load(input);

var moduleId = reg.ModuleName.Replace('.', '_');

var cPath = Path.Combine(outputDir, $"{moduleId}.c");
File.WriteAllText(cPath, App.GenerateC(reg));
Console.WriteLine($"Generated: {cPath}");

var luaPath = Path.Combine(outputDir, $"{moduleId}.lua");
File.WriteAllText(luaPath, App.GenerateLua(reg));
Console.WriteLine($"Generated: {luaPath}");

return 0;
