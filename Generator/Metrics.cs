namespace Generator;

using Generator.ClangAst;

public record ModuleMetrics(
    string ModuleName,
    int ParsedFuncs, int ParsedStructs, int ParsedEnums,
    int BoundFuncs, int BoundStructs, int BoundEnums,
    int LuaCatsFuncs, int LuaCatsStructs, int LuaCatsEnums)
{
    public int ParsedTotal => ParsedFuncs + ParsedStructs + ParsedEnums;
    public int BoundTotal => BoundFuncs + BoundStructs + BoundEnums;
    public int LuaCatsTotal => LuaCatsFuncs + LuaCatsStructs + LuaCatsEnums;

    public static ModuleMetrics Collect(string moduleName, TypeRegistry reg, ModuleSpec spec)
    {
        // Parsed: Clang AST declarations (IsDep=false)
        var parsedFuncs = reg.OwnFuncs.Count();
        var parsedStructs = reg.OwnStructs.Count();
        var parsedEnums = reg.OwnEnums.Count();

        // Bound: C binding code generated
        var boundFuncs = spec.Funcs.Count
                       + spec.ExtraLuaRegs.Count
                       + spec.ArrayAdapters.Count
                       + spec.EventAdapters.Count
                       + spec.OpaqueTypes.Count(ot => ot.InitFunc != null)
                       + spec.OpaqueTypes.Sum(ot => ot.Methods.Count);

        var boundStructs = spec.Structs.Count + spec.OpaqueTypes.Count;
        var boundEnums = spec.Enums.Count;

        // LuaCATS: type annotations generated
        var luaCatsFuncs = spec.Funcs.Count
                         + spec.ExtraLuaFuncs.Count
                         + spec.ArrayAdapters.Count
                         + spec.EventAdapters.Count
                         + spec.OpaqueTypes.Count(ot => ot.InitFunc != null)
                         + spec.OpaqueTypes.Sum(ot => ot.Methods.Count);

        var luaCatsStructs = spec.Structs.Count + spec.OpaqueTypes.Count;
        var luaCatsEnums = spec.Enums.Count;

        return new ModuleMetrics(
            moduleName,
            parsedFuncs, parsedStructs, parsedEnums,
            boundFuncs, boundStructs, boundEnums,
            luaCatsFuncs, luaCatsStructs, luaCatsEnums);
    }

    public static UnboundReport CollectUnbound(string moduleName, TypeRegistry reg, ModuleSpec spec)
    {
        // Bound func names (original parsed names)
        var boundFuncNames = new HashSet<string>();
        foreach (var f in spec.Funcs)
            boundFuncNames.Add(f.CppFuncName ?? f.CName);
        foreach (var ot in spec.OpaqueTypes)
        {
            foreach (var m in ot.Methods)
                boundFuncNames.Add(m.CName);
            if (ot.InitFunc != null) boundFuncNames.Add(ot.InitFunc);
            if (ot.UninitFunc != null) boundFuncNames.Add(ot.UninitFunc);
        }
        // ExtraLuaRegs: CFunc is "l_{original}" — strip "l_" to recover parsed name
        foreach (var (_, cFunc) in spec.ExtraLuaRegs)
        {
            if (cFunc.StartsWith("l_"))
                boundFuncNames.Add(cFunc[2..]);
        }

        // Bound struct names
        var boundStructNames = new HashSet<string>();
        foreach (var s in spec.Structs)
            boundStructNames.Add(s.CName);
        foreach (var ot in spec.OpaqueTypes)
            boundStructNames.Add(ot.CName);

        // Bound enum names
        var boundEnumNames = new HashSet<string>();
        foreach (var e in spec.Enums)
            boundEnumNames.Add(e.CName);

        var unboundFuncs = reg.OwnFuncs
            .Where(f => !boundFuncNames.Contains(f.Name))
            .Select(f => f.Name).Order().ToList();
        var unboundStructs = reg.OwnStructs
            .Where(s => !boundStructNames.Contains(s.Name))
            .Select(s => s.Name).Order().ToList();
        var unboundEnums = reg.OwnEnums
            .Where(e => !boundEnumNames.Contains(e.Name))
            .Select(e => e.Name).Order().ToList();

        return new UnboundReport(moduleName, unboundFuncs, unboundStructs, unboundEnums);
    }

    public static void PrintUnbound(IEnumerable<UnboundReport> reports)
    {
        var list = reports.Where(r => r.Total > 0).ToList();
        if (list.Count == 0) return;

        Console.WriteLine("=== Unbound Declarations ===");
        Console.WriteLine();

        foreach (var r in list)
        {
            Console.WriteLine($"[{r.ModuleName}] {r.Funcs.Count} funcs, {r.Structs.Count} structs, {r.Enums.Count} enums");
            if (r.Funcs.Count > 0)
                Console.WriteLine($"  funcs: {string.Join(", ", r.Funcs)}");
            if (r.Structs.Count > 0)
                Console.WriteLine($"  structs: {string.Join(", ", r.Structs)}");
            if (r.Enums.Count > 0)
                Console.WriteLine($"  enums: {string.Join(", ", r.Enums)}");
        }

        Console.WriteLine();
    }

    private static string Pct(int part, int whole) =>
        whole > 0 ? $"{100 * part / whole,3}%" : "  - ";

    public static void PrintTable(IEnumerable<ModuleMetrics> metrics)
    {
        var list = metrics.ToList();
        if (list.Count == 0) return;

        var nameWidth = Math.Max(6, list.Max(m => m.ModuleName.Length));

        Console.WriteLine();
        Console.WriteLine("=== Generator Metrics ===");
        Console.WriteLine();

        // Header
        var header = string.Format(
            "{0}  | {1} | {2} | {3}",
            "Module".PadRight(nameWidth),
            "  Parsed (F/S/E) ",
            "  Bound (F/S/E)   Cov",
            " LuaCATS (F/S/E)  Cov");
        Console.WriteLine(header);
        Console.WriteLine(new string('-', header.Length));

        foreach (var m in list)
        {
            Console.WriteLine(
                "{0}  | {1,5}/{2,4}/{3,4}  | {4,5}/{5,4}/{6,4}  {7} | {8,5}/{9,4}/{10,4}  {11}",
                m.ModuleName.PadRight(nameWidth),
                m.ParsedFuncs, m.ParsedStructs, m.ParsedEnums,
                m.BoundFuncs, m.BoundStructs, m.BoundEnums,
                Pct(m.BoundTotal, m.ParsedTotal),
                m.LuaCatsFuncs, m.LuaCatsStructs, m.LuaCatsEnums,
                Pct(m.LuaCatsTotal, m.ParsedTotal));
        }

        // Total row
        Console.WriteLine(new string('-', header.Length));
        var total = new ModuleMetrics(
            "TOTAL",
            list.Sum(m => m.ParsedFuncs), list.Sum(m => m.ParsedStructs), list.Sum(m => m.ParsedEnums),
            list.Sum(m => m.BoundFuncs), list.Sum(m => m.BoundStructs), list.Sum(m => m.BoundEnums),
            list.Sum(m => m.LuaCatsFuncs), list.Sum(m => m.LuaCatsStructs), list.Sum(m => m.LuaCatsEnums));
        Console.WriteLine(
            "{0}  | {1,5}/{2,4}/{3,4}  | {4,5}/{5,4}/{6,4}  {7} | {8,5}/{9,4}/{10,4}  {11}",
            total.ModuleName.PadRight(nameWidth),
            total.ParsedFuncs, total.ParsedStructs, total.ParsedEnums,
            total.BoundFuncs, total.BoundStructs, total.BoundEnums,
            Pct(total.BoundTotal, total.ParsedTotal),
            total.LuaCatsFuncs, total.LuaCatsStructs, total.LuaCatsEnums,
            Pct(total.LuaCatsTotal, total.ParsedTotal));

        Console.WriteLine();
    }
}

public record UnboundReport(
    string ModuleName,
    List<string> Funcs,
    List<string> Structs,
    List<string> Enums)
{
    public int Total => Funcs.Count + Structs.Count + Enums.Count;
}
