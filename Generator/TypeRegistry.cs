using System.Collections.Generic;
using System.Text.Json;

namespace Generator.ClangAst;

/// <summary>
/// JSON から型を辞書として保持し、名前でアクセス可能にする
/// </summary>
public class TypeRegistry
{
    private readonly Module _module;
    private readonly OrderedDictionary<string, Decl> _decls;

    private TypeRegistry(Module module)
    {
        _module = module;
        _decls = new OrderedDictionary<string, Decl>();

        foreach (var decl in module.Decls)
        {
            var name = decl switch
            {
                Structs s => s.Name,
                Funcs f => f.Name,
                Enums e => e.Name,
                Consts => null,
                _ => null
            };
            if (name != null)
                _decls[name] = decl;
        }
    }

    public static TypeRegistry FromJson(string json)
    {
        var module = JsonSerializer.Deserialize<Module>(json)!;
        return new TypeRegistry(module);
    }

    public static TypeRegistry Load(string path)
    {
        var json = File.ReadAllText(path);
        return FromJson(json);
    }

    public string ModuleName => _module.Name;
    public string Prefix => _module.Prefix;
    public List<string> DepPrefixes => _module.DepPrefixes;

    public Decl this[string name] => _decls[name];

    public Structs GetStruct(string name) => (Structs)_decls[name];
    public Funcs GetFunc(string name) => (Funcs)_decls[name];
    public Enums GetEnum(string name) => (Enums)_decls[name];

    public IEnumerable<Decl> AllDecls => _module.Decls;
}
