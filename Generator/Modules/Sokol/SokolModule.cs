namespace Generator.Modules.Sokol;

using Generator.ClangAst;

/// <summary>
/// Sokol モジュール共通基底クラス — TypeRegistry から ModuleSpec を自動構築
/// </summary>
public abstract class SokolModule : IModule
{
    public abstract string ModuleName { get; }
    public abstract string Header { get; }
    public abstract string Prefix { get; }
    public virtual IReadOnlyList<string> IncludeDirs => ["sokol"];
    public virtual IReadOnlyList<string> DepPrefixes => [];

    // ===== カスタマイズ hooks (virtual) =====

    protected virtual IReadOnlySet<string> Ignores => new HashSet<string>();
    protected virtual bool ShouldGenerateFunc(Funcs f) => true;
    protected virtual bool HasMetamethods(Structs s) => false;
    protected virtual string MapFieldName(string fieldName) => fieldName;
    protected virtual BindingType ResolveType(Types t, string moduleName, string prefix) =>
        DefaultResolveType(t, moduleName, prefix);
    protected virtual string? ExtraCCode(TypeRegistry reg) => null;
    protected virtual IEnumerable<(string LuaName, string CFunc)> ExtraLuaRegs => [];

    // ===== BuildSpec =====

    public ModuleSpec BuildSpec(TypeRegistry reg, SourceLink? sourceLink = null)
    {
        var structs = new List<StructBinding>();
        foreach (var s in reg.OwnStructs)
        {
            if (Ignores.Contains(s.Name)) continue;
            var pascalName = Pipeline.ToPascalCase(Pipeline.StripPrefix(s.Name, Prefix));
            var metatable = $"{ModuleName}.{pascalName}";
            var fields = s.Fields.Select(f => new FieldBinding(
                f.Name,
                MapFieldName(f.Name),
                ResolveType(f.ParsedType, ModuleName, Prefix)
            )).ToList();
            structs.Add(new StructBinding(
                s.Name, pascalName, metatable,
                HasMetamethods(s), fields,
                GetLink(s, sourceLink)));
        }

        var funcs = new List<FuncBinding>();
        foreach (var f in reg.OwnFuncs)
        {
            if (Ignores.Contains(f.Name)) continue;
            if (!ShouldGenerateFunc(f)) continue;
            var luaName = Pipeline.ToPascalCase(Pipeline.StripPrefix(f.Name, Prefix));
            var parms = f.Params.Select(p => new ParamBinding(
                p.Name,
                ResolveType(p.ParsedType, ModuleName, Prefix)
            )).ToList();
            var retType = ResolveType(CTypeParser.ParseReturnType(f.TypeStr), ModuleName, Prefix);
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

        var includes = DepPrefixes.Count > 0
            ? DepPrefixes.Select(_ => "sokol_log.h").Concat([Path.GetFileName(Header)]).ToList()
            : [Path.GetFileName(Header)];

        return new ModuleSpec(
            ModuleName, Prefix, includes,
            ExtraCCode(reg),
            structs, funcs, enums,
            ExtraLuaRegs.ToList());
    }

    // ===== IModule 実装 =====

    public string GenerateC(TypeRegistry reg)
    {
        var spec = BuildSpec(reg);
        return CBinding.CBindingGen.Generate(spec);
    }

    public string GenerateLua(TypeRegistry reg, SourceLink? sourceLink = null)
    {
        var spec = BuildSpec(reg, sourceLink);
        return LuaCats.LuaCatsGen.Generate(spec);
    }

    // ===== デフォルト型変換 =====

    protected static BindingType DefaultResolveType(Types t, string moduleName, string prefix) => t switch
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
        Types.Ptr(Types.Void) => new BindingType.VoidPtr(),
        Types.Ptr(var inner) => new BindingType.Ptr(DefaultResolveType(inner, moduleName, prefix)),
        Types.ConstPtr(var inner) => new BindingType.ConstPtr(DefaultResolveType(inner, moduleName, prefix)),
        Types.FuncPtr(var args, var ret) => new BindingType.Callback(
            args.Select((a, i) => ($"arg{i}", DefaultResolveType(a, moduleName, prefix))).ToList(),
            ret is Types.Void ? null : DefaultResolveType(ret, moduleName, prefix)),
        Types.StructRef(var name) => new BindingType.Struct(
            name,
            $"{moduleName}.{Pipeline.ToPascalCase(Pipeline.StripPrefix(name, prefix))}",
            $"{moduleName}.{Pipeline.ToPascalCase(Pipeline.StripPrefix(name, prefix))}"),
        Types.Void => new BindingType.Void(),
        _ => new BindingType.Void()
    };

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
