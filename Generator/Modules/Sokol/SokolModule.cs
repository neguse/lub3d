namespace Generator.Modules.Sokol;

using Generator.ClangAst;

/// <summary>
/// Sokol モジュール共通基底クラス — TypeRegistry から ModuleSpec を自動構築
/// </summary>
public abstract class SokolModule : IModule
{
    public abstract string ModuleName { get; }
    public abstract string Prefix { get; }

    // ===== カスタマイズ hooks (virtual) =====

    protected virtual IReadOnlySet<string> Ignores => new HashSet<string>();
    protected virtual bool ShouldGenerateFunc(Funcs f) => true;
    protected virtual bool HasMetamethods(Structs s) => false;
    protected virtual string MapFieldName(string fieldName) => fieldName;
    protected virtual BindingType ResolveType(Types t, string moduleName, string prefix, Dictionary<string, string> prefixToModule) =>
        DefaultResolveType(t, moduleName, prefix, prefixToModule);
    protected virtual string? ExtraCCode(TypeRegistry reg) => null;
    protected virtual IEnumerable<(string LuaName, string CFunc)> ExtraLuaRegs => [];
    protected virtual IEnumerable<FuncBinding> ExtraLuaFuncs => [];

    // ===== CollectSkips =====

    public virtual SkipReport CollectSkips(TypeRegistry reg) => new(ModuleName, [], [], []);

    // ===== BuildSpec =====

    public ModuleSpec BuildSpec(TypeRegistry reg, Dictionary<string, string> prefixToModule, SourceLink? sourceLink = null)
    {
        var enumNames = reg.AllDecls.OfType<Enums>().Select(e => e.Name).ToHashSet();

        BindingType Resolve(Types t)
        {
            if (t is Types.StructRef(var name) && enumNames.Contains(name))
            {
                var matchedPrefix = prefixToModule.Keys
                    .OrderByDescending(p => p.Length)
                    .FirstOrDefault(p => name.StartsWith(p));
                var ownerModule = matchedPrefix != null ? prefixToModule[matchedPrefix] : ModuleName;
                var stripPrefix = matchedPrefix ?? Prefix;
                var luaName = $"{ownerModule}.{Pipeline.ToPascalCase(Pipeline.StripPrefix(name, stripPrefix))}";
                return new BindingType.Enum(name, luaName);
            }
            return ResolveType(t, ModuleName, Prefix, prefixToModule);
        }

        var structs = new List<StructBinding>();
        foreach (var s in reg.OwnStructs)
        {
            if (Ignores.Contains(s.Name)) continue;
            var pascalName = Pipeline.ToPascalCase(Pipeline.StripTypeSuffix(Pipeline.StripPrefix(s.Name, Prefix)));
            var metatable = $"{ModuleName}.{pascalName}";
            var fields = s.Fields.Select(f => new FieldBinding(
                f.Name,
                MapFieldName(f.Name),
                Resolve(f.ParsedType)
            )).ToList();
            structs.Add(new StructBinding(
                s.Name, pascalName, metatable,
                HasMetamethods(s), fields,
                GetLink(s, sourceLink),
                AllowStringInit: s.Name == "sg_range"));
        }

        var funcs = new List<FuncBinding>();
        foreach (var f in reg.OwnFuncs)
        {
            if (Ignores.Contains(f.Name)) continue;
            if (!ShouldGenerateFunc(f)) continue;
            var luaName = Pipeline.StripPrefix(f.Name, Prefix);
            var parms = f.Params.Select(p => new ParamBinding(
                p.Name,
                Resolve(p.ParsedType)
            )).ToList();
            var retType = Resolve(CTypeParser.ParseReturnType(f.TypeStr));
            funcs.Add(new FuncBinding(
                f.Name, luaName, parms, retType,
                GetLink(f, sourceLink)));
        }

        var enums = new List<EnumBinding>();
        foreach (var e in reg.OwnEnums)
        {
            if (Ignores.Contains(e.Name)) continue;
            var luaName = $"{ModuleName}.{Pipeline.ToPascalCase(Pipeline.StripPrefix(e.Name, Prefix))}";
            var fieldName = Pipeline.ToPascalCase(Pipeline.StripPrefix(e.Name, Prefix));
            var next = 0;
            var items = e.Items.Where(i => !i.Name.StartsWith("_")).Select(i =>
            {
                int? val = i.Value != null && int.TryParse(i.Value, out var v) ? v : null;
                var resolvedVal = val ?? next;
                next = resolvedVal + 1;
                var itemName = Pipeline.EnumItemName(i.Name, e.Name, Prefix);
                return new EnumItemBinding(itemName, i.Name, resolvedVal);
            }).ToList();
            enums.Add(new EnumBinding(
                e.Name, luaName, fieldName, items,
                GetLink(e, sourceLink)));
        }

        var includes = new List<string>
        {
            "sokol_log.h", "sokol_gfx.h", "sokol_app.h", "sokol_time.h",
            "sokol_audio.h", "sokol_gl.h", "sokol_debugtext.h",
            "sokol_shape.h", "sokol_glue.h", "sokol_imgui.h"
        };

        return new ModuleSpec(
            ModuleName, Prefix, includes,
            ExtraCCode(reg),
            structs, funcs, enums,
            ExtraLuaRegs.ToList(),
            ExtraLuaFuncs: ExtraLuaFuncs.ToList());
    }

    // ===== IModule 実装 =====

    public string GenerateC(TypeRegistry reg, Dictionary<string, string> prefixToModule)
    {
        var spec = BuildSpec(reg, prefixToModule);
        return CBinding.CBindingGen.Generate(spec);
    }

    public string GenerateLua(TypeRegistry reg, Dictionary<string, string> prefixToModule, SourceLink? sourceLink = null)
    {
        var spec = BuildSpec(reg, prefixToModule, sourceLink);
        return LuaCats.LuaCatsGen.Generate(spec);
    }

    // ===== デフォルト型変換 =====

    protected static BindingType DefaultResolveType(Types t, string moduleName, string prefix, Dictionary<string, string> prefixToModule) => t switch
    {
        Types.Int => new BindingType.Int(),
        Types.Int64 => new BindingType.Int64(),
        Types.UInt32 => new BindingType.UInt32(),
        Types.UInt64 => new BindingType.UInt64(),
        Types.Size => new BindingType.Size(),
        Types.UIntPtr => new BindingType.UIntPtr(),
        Types.IntPtr => new BindingType.IntPtr(),
        Types.Float => new BindingType.Float(),
        Types.Double => new BindingType.Double(),
        Types.Bool => new BindingType.Bool(),
        Types.String => new BindingType.Str(),
        Types.Array(var inner, var len) => new BindingType.FixedArray(
            DefaultResolveType(inner, moduleName, prefix, prefixToModule), len),
        Types.Ptr(Types.Void) => new BindingType.VoidPtr(),
        Types.Ptr(var inner) => new BindingType.Ptr(DefaultResolveType(inner, moduleName, prefix, prefixToModule)),
        Types.ConstPtr(var inner) => new BindingType.ConstPtr(DefaultResolveType(inner, moduleName, prefix, prefixToModule)),
        Types.FuncPtr(var args, var ret) => new BindingType.Callback(
            args.Select((a, i) => ($"arg{i}", DefaultResolveType(a, moduleName, prefix, prefixToModule))).ToList(),
            ret is Types.Void ? null : DefaultResolveType(ret, moduleName, prefix, prefixToModule)),
        Types.StructRef(var name) => ResolveStructRef(name, moduleName, prefix, prefixToModule),
        Types.Void => new BindingType.Void(),
        _ => new BindingType.Void()
    };

    private static BindingType ResolveStructRef(string name, string moduleName, string prefix, Dictionary<string, string> prefixToModule)
    {
        // Try to find the owning module by prefix match
        var matchedPrefix = prefixToModule.Keys
            .OrderByDescending(p => p.Length)
            .FirstOrDefault(p => name.StartsWith(p));
        var ownerModule = matchedPrefix != null ? prefixToModule[matchedPrefix] : moduleName;
        var stripPrefix = matchedPrefix ?? prefix;
        var pascal = Pipeline.ToPascalCase(Pipeline.StripTypeSuffix(Pipeline.StripPrefix(name, stripPrefix)));
        var fullName = $"{ownerModule}.{pascal}";
        return new BindingType.Struct(name, fullName, fullName);
    }

    // ===== ヘルパー =====

    private static string? GetLink(Decl d, SourceLink? sourceLink)
    {
        if (sourceLink == null) return null;
        var line = d switch
        {
            Structs s => s.Line,
            Funcs f => f.Line,
            Enums e => e.Line,
            _ => null
        };
        return line is int l ? sourceLink.GetLink(l) : null;
    }
}
