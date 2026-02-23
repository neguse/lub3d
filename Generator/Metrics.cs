namespace Generator;

using Generator.ClangAst;

public record SkipEntry(string Name, string Reason);

public record SkipReport(
    string ModuleName,
    List<SkipEntry> Funcs,
    List<SkipEntry> Structs,
    List<SkipEntry> Enums)
{
    public int Total => Funcs.Count + Structs.Count + Enums.Count;
    public bool IsAudited => Total > 0;
}

public record ModuleMetrics(
    string ModuleName,
    int ParsedFuncs, int ParsedStructs, int ParsedEnums,
    int BoundFuncs, int BoundStructs, int BoundEnums,
    int SkippedFuncs, int SkippedStructs, int SkippedEnums,
    int LuaCatsFuncs, int LuaCatsStructs, int LuaCatsEnums)
{
    public int ParsedTotal => ParsedFuncs + ParsedStructs + ParsedEnums;
    public int BoundTotal => BoundFuncs + BoundStructs + BoundEnums;
    public int SkippedTotal => SkippedFuncs + SkippedStructs + SkippedEnums;
    public int LuaCatsTotal => LuaCatsFuncs + LuaCatsStructs + LuaCatsEnums;

    public static ModuleMetrics Collect(string moduleName, TypeRegistry reg, ModuleSpec spec, SkipReport? skip = null)
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
                       + spec.OpaqueTypes.Count(ot => ot.UninitFunc != null)
                       + spec.OpaqueTypes.Count(ot => ot.ConfigInitFunc != null)
                       + spec.OpaqueTypes.Sum(ot => ot.Methods.Count);

        var boundStructs = spec.Structs.Count + spec.OpaqueTypes.Count;
        var boundEnums = spec.Enums.Count;

        // Skipped: intentionally not bound (with reason)
        var skippedFuncs = skip?.Funcs.Count ?? 0;
        var skippedStructs = skip?.Structs.Count ?? 0;
        var skippedEnums = skip?.Enums.Count ?? 0;

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
            skippedFuncs, skippedStructs, skippedEnums,
            luaCatsFuncs, luaCatsStructs, luaCatsEnums);
    }

    public static (UnboundReport Unhandled, SkipReport? Skipped) CollectUnbound(
        string moduleName, TypeRegistry reg, ModuleSpec spec, SkipReport? skip = null)
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
            if (ot.ConfigInitFunc != null) boundFuncNames.Add(ot.ConfigInitFunc);
        }
        // ExtraLuaRegs: CFunc is "l_{original}" — strip "l_" to recover parsed name
        foreach (var (_, cFunc) in spec.ExtraLuaRegs)
        {
            if (cFunc.StartsWith("l_"))
                boundFuncNames.Add(cFunc[2..]);
        }
        // ArrayAdapters: fill function is bound
        foreach (var aa in spec.ArrayAdapters)
            boundFuncNames.Add(aa.FillFuncCName);
        // EventAdapters: C function is bound
        foreach (var ea in spec.EventAdapters)
            boundFuncNames.Add(ea.CFuncName);

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

        // Skipped names
        var skippedFuncNames = skip?.Funcs.Select(s => s.Name).ToHashSet() ?? [];
        var skippedStructNames = skip?.Structs.Select(s => s.Name).ToHashSet() ?? [];
        var skippedEnumNames = skip?.Enums.Select(s => s.Name).ToHashSet() ?? [];

        // Unhandled = parsed - bound - skipped
        var unboundFuncs = reg.OwnFuncs
            .Where(f => !boundFuncNames.Contains(f.Name) && !skippedFuncNames.Contains(f.Name))
            .Select(f => f.Name).Order().ToList();
        var unboundStructs = reg.OwnStructs
            .Where(s => !boundStructNames.Contains(s.Name) && !skippedStructNames.Contains(s.Name))
            .Select(s => s.Name).Order().ToList();
        var unboundEnums = reg.OwnEnums
            .Where(e => !boundEnumNames.Contains(e.Name) && !skippedEnumNames.Contains(e.Name))
            .Select(e => e.Name).Order().ToList();

        return (
            new UnboundReport(moduleName, unboundFuncs, unboundStructs, unboundEnums),
            skip);
    }

    public static void PrintUnbound(IEnumerable<(UnboundReport Unhandled, SkipReport? Skipped)> reports)
    {
        var list = reports.ToList();

        // Unhandled declarations
        var unhandled = list.Select(r => r.Unhandled).Where(r => r.Total > 0).ToList();
        if (unhandled.Count > 0)
        {
            Console.WriteLine("=== Unhandled Declarations ===");
            Console.WriteLine();

            foreach (var r in unhandled)
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

        // Intentionally skipped
        var skipped = list
            .Where(r => r.Skipped != null && r.Skipped.Total > 0)
            .Select(r => r.Skipped!)
            .ToList();
        if (skipped.Count > 0)
        {
            Console.WriteLine("=== Intentionally Skipped ===");
            Console.WriteLine();

            foreach (var r in skipped)
            {
                var parts = new List<string>();
                if (r.Funcs.Count > 0) parts.Add($"{r.Funcs.Count} funcs");
                if (r.Structs.Count > 0) parts.Add($"{r.Structs.Count} structs");
                if (r.Enums.Count > 0) parts.Add($"{r.Enums.Count} enums");
                Console.WriteLine($"[{r.ModuleName}] {string.Join(", ", parts)}");

                foreach (var e in r.Funcs.DistinctBy(e => e.Name))
                    Console.WriteLine($"  {e.Name}: {e.Reason}");
                foreach (var e in r.Structs.DistinctBy(e => e.Name))
                    Console.WriteLine($"  {e.Name}: {e.Reason}");
                foreach (var e in r.Enums.DistinctBy(e => e.Name))
                    Console.WriteLine($"  {e.Name}: {e.Reason}");
            }

            Console.WriteLine();
        }
    }

    private static string Pct(int part, int whole) =>
        whole > 0 ? $"{100 * part / whole,3}%" : "  - ";

    private static string AudCov(int bound, int parsed, int skipped)
    {
        if (skipped == 0) return "  - ";
        var denominator = parsed - skipped;
        if (denominator <= 0) return "  - ";
        var pct = Math.Min(100, 100 * bound / denominator);
        return $"{pct,3}%";
    }

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
            "{0}  | {1} | {2} | {3} | {4}",
            "Module".PadRight(nameWidth),
            "  Parsed (F/S/E) ",
            "  Bound (F/S/E)   Cov",
            "Skipped AudCov",
            " LuaCATS (F/S/E)  Cov");
        Console.WriteLine(header);
        Console.WriteLine(new string('-', header.Length));

        foreach (var m in list)
        {
            Console.WriteLine(
                "{0}  | {1,5}/{2,4}/{3,4}  | {4,5}/{5,4}/{6,4}  {7} | {8,5}  {9} | {10,5}/{11,4}/{12,4}  {13}",
                m.ModuleName.PadRight(nameWidth),
                m.ParsedFuncs, m.ParsedStructs, m.ParsedEnums,
                m.BoundFuncs, m.BoundStructs, m.BoundEnums,
                Pct(m.BoundTotal, m.ParsedTotal),
                m.SkippedTotal,
                AudCov(m.BoundTotal, m.ParsedTotal, m.SkippedTotal),
                m.LuaCatsFuncs, m.LuaCatsStructs, m.LuaCatsEnums,
                Pct(m.LuaCatsTotal, m.ParsedTotal));
        }

        // Total row
        Console.WriteLine(new string('-', header.Length));
        var total = new ModuleMetrics(
            "TOTAL",
            list.Sum(m => m.ParsedFuncs), list.Sum(m => m.ParsedStructs), list.Sum(m => m.ParsedEnums),
            list.Sum(m => m.BoundFuncs), list.Sum(m => m.BoundStructs), list.Sum(m => m.BoundEnums),
            list.Sum(m => m.SkippedFuncs), list.Sum(m => m.SkippedStructs), list.Sum(m => m.SkippedEnums),
            list.Sum(m => m.LuaCatsFuncs), list.Sum(m => m.LuaCatsStructs), list.Sum(m => m.LuaCatsEnums));
        Console.WriteLine(
            "{0}  | {1,5}/{2,4}/{3,4}  | {4,5}/{5,4}/{6,4}  {7} | {8,5}  {9} | {10,5}/{11,4}/{12,4}  {13}",
            total.ModuleName.PadRight(nameWidth),
            total.ParsedFuncs, total.ParsedStructs, total.ParsedEnums,
            total.BoundFuncs, total.BoundStructs, total.BoundEnums,
            Pct(total.BoundTotal, total.ParsedTotal),
            total.SkippedTotal,
            AudCov(total.BoundTotal, total.ParsedTotal, total.SkippedTotal),
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
