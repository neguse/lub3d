namespace Generator.Modules.Imgui;

using Generator.ClangAst;
using ClangParam = Generator.ClangAst.Param;

/// <summary>
/// Dear ImGui モジュール — IModule 直接実装 (SokolModule 非継承)
/// C++ namespace ベースの関数を ModuleSpec に変換
/// </summary>
public class ImguiModule : IModule
{
    public string ModuleName => "imgui";
    public string Prefix => "";

    /// <summary>
    /// Lua 予約語回避のためのリネームマップ
    /// "End" → "end_window" (end は Lua 予約語)、対称性のため "Begin" も "begin_window"
    /// </summary>
    private static readonly Dictionary<string, string> FunctionRenames = new()
    {
        ["Begin"] = "begin_window",
        ["End"] = "end_window",
    };

    private static readonly HashSet<string> SkipFunctions =
    [
        "GetIO", "GetPlatformIO", "GetStyle", "GetDrawData",
        "GetCurrentContext", "SetCurrentContext", "CreateContext", "DestroyContext",
        "SetNextWindowSizeConstraints", "SetAllocatorFunctions", "GetAllocatorFunctions",
        "GetWindowDrawList", "GetBackgroundDrawList", "GetForegroundDrawList",
        "GetFont", "GetFontBaked",
        "BeginMultiSelect", "EndMultiSelect", "SetNextItemSelectionUserData",
        "GetMainViewport",
        "Image", "ImageWithBg", "ImageButton",
        "ShowStyleEditor", "StyleColorsDark", "StyleColorsLight", "StyleColorsClassic",
        "PushFont", "PopFont",
        "InputText", "InputTextMultiline", "InputTextWithHint",
        "ColorPicker4", "ColorConvertRGBtoHSV", "ColorConvertHSVtoRGB",
        "SetStateStorage", "GetStateStorage",
        "SaveIniSettingsToMemory", "LoadIniSettingsFromMemory",
        "IsMousePosValid",
        "Shortcut", "SetNextItemShortcut",
        "NewFrame", "Render", "EndFrame",
        // Complex return types / internal APIs
        "DebugLog", "DebugLogV",
        "MemAlloc", "MemFree",
        "ListBox", "Combo",
        "PlotLines", "PlotHistogram",
    ];

    private static readonly HashSet<string> FloatArrayParamNames =
        ["col", "v", "color", "values", "ref_col"];

    public ModuleSpec BuildSpec(TypeRegistry reg, Dictionary<string, string> prefixToModule, SourceLink? sourceLink = null)
    {
        var funcs = reg.AllDecls.OfType<Funcs>()
            .Where(f => f.Namespace == "ImGui")
            .ToList();

        var enums = reg.AllDecls.OfType<Enums>()
            .Where(e => e.Name.StartsWith("ImGui"))
            .GroupBy(e => e.Name)
            .Select(g => g.First())
            .ToList();

        // Detect overloads
        var nameCounts = funcs.GroupBy(f => f.Name).ToDictionary(g => g.Key, g => g.Count());

        var funcBindings = new List<FuncBinding>();
        var seenNames = new Dictionary<string, int>();

        foreach (var f in funcs)
        {
            if (SkipFunctions.Contains(f.Name)) continue;
            if (IsVararg(f)) continue;
            if (HasUnsupportedParam(f)) continue;

            var luaName = FunctionRenames.GetValueOrDefault(f.Name, Pipeline.ToSnakeCase(f.Name));
            if (nameCounts[f.Name] > 1)
            {
                luaName = MakeOverloadName(f);
                // Ensure uniqueness
                if (seenNames.TryGetValue(luaName, out var count))
                {
                    seenNames[luaName] = count + 1;
                    luaName = $"{luaName}{count + 1}";
                }
                else
                {
                    seenNames[luaName] = 1;
                }
            }

            var parms = ConvertParams(f);
            var retType = ConvertReturnType(f.TypeStr);
            var isOverload = nameCounts[f.Name] > 1;
            // CName must be unique for l_CName; use luaName for overloaded funcs
            var cName = isOverload ? luaName : f.Name;
            funcBindings.Add(new FuncBinding(cName, luaName, parms, retType, null,
                CppNamespace: "ImGui", CppFuncName: isOverload ? f.Name : null));
        }

        var enumBindings = enums.Select(ConvertEnum).ToList();

        // sokol_imgui 統合関数 (imgui_sokol.cpp で手書き登録)
        var extraLuaFuncs = new List<FuncBinding>
        {
            new("l_imgui_setup", "setup",
                [new ParamBinding("opts", new BindingType.Custom("table", "table", "", "", "", ""), IsOptional: true)],
                new BindingType.Void(), null),
            new("l_imgui_shutdown", "shutdown", [], new BindingType.Void(), null),
            new("l_imgui_new_frame", "new_frame", [], new BindingType.Void(), null),
            new("l_imgui_render", "render", [], new BindingType.Void(), null),
            new("l_imgui_handle_event", "handle_event",
                [new ParamBinding("ev", new BindingType.VoidPtr())],
                new BindingType.Bool(), null),
        };

        return new ModuleSpec(
            ModuleName, "",
            ["imgui.h"], null,
            [], // Structs = empty
            funcBindings,
            enumBindings,
            [],
            IsCpp: true,
            EntryPoint: "luaopen_imgui_gen",
            ExtraLuaFuncs: extraLuaFuncs);
    }

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

    // ===== 型変換 =====

    private List<ParamBinding> ConvertParams(Funcs f)
    {
        var result = new List<ParamBinding>();
        var funcName = f.Name;
        var floatArraySize = DetectFloatArraySize(funcName);

        foreach (var p in f.Params)
        {
            var type = ConvertParamType(p, funcName, floatArraySize);
            var isOptional = p.HasDefault;
            var isOutput = IsOutputParam(p, floatArraySize);
            result.Add(new ParamBinding(p.Name, type, isOptional, isOutput));
        }

        return result;
    }

    private BindingType ConvertParamType(ClangParam p, string funcName, int floatArraySize)
    {
        var typeStr = p.TypeStr.Trim();

        // Float array detection
        if (typeStr == "float *" && floatArraySize > 0 && FloatArrayParamNames.Contains(p.Name))
            return new BindingType.FloatArray(floatArraySize);

        // Output params (non-const pointer)
        if (typeStr == "bool *")
            return new BindingType.Bool();
        if (typeStr == "int *")
            return new BindingType.Int();
        if (typeStr == "float *")
            return new BindingType.Float();
        if (typeStr == "double *")
            return new BindingType.Double();
        if (typeStr == "unsigned int *")
            return new BindingType.UInt32();

        // ImVec2/ImVec4 (by value or const ref)
        if (typeStr is "const ImVec2 &" or "ImVec2" or "const ImVec2")
            return new BindingType.Vec2();
        if (typeStr is "const ImVec4 &" or "ImVec4" or "const ImVec4")
            return new BindingType.Vec4();

        return ConvertBasicType(typeStr);
    }

    private BindingType ConvertReturnType(string funcTypeStr)
    {
        var parenIdx = funcTypeStr.IndexOf('(');
        var retStr = parenIdx > 0 ? funcTypeStr[..parenIdx].Trim() : "void";

        if (retStr is "ImVec2" or "const ImVec2 &")
            return new BindingType.Vec2();
        if (retStr is "ImVec4" or "const ImVec4 &")
            return new BindingType.Vec4();

        return ConvertBasicType(retStr);
    }

    private static BindingType ConvertBasicType(string typeStr) => typeStr switch
    {
        "void" => new BindingType.Void(),
        "bool" => new BindingType.Bool(),
        "int" or "int32_t" => new BindingType.Int(),
        "unsigned int" or "uint32_t" => new BindingType.UInt32(),
        "int64_t" => new BindingType.Int64(),
        "uint64_t" => new BindingType.UInt64(),
        "float" => new BindingType.Float(),
        "double" => new BindingType.Double(),
        "const char *" => new BindingType.Str(),
        "size_t" => new BindingType.Size(),
        _ when typeStr.StartsWith("ImGui") && typeStr.EndsWith("_") =>
            new BindingType.Enum(typeStr, $"imgui.{StripImGuiPrefix(typeStr)}"),
        _ when typeStr.StartsWith("ImGui") =>
            new BindingType.Enum(typeStr, $"imgui.{StripImGuiPrefix(typeStr)}"),
        _ => new BindingType.Int() // fallback
    };

    // ===== ヘルパー =====

    private static bool IsVararg(Funcs f) => f.TypeStr.Contains("...");

    private static bool HasUnsupportedParam(Funcs f)
    {
        // Check return type for unsupported types
        var retStr = f.TypeStr;
        var parenIdx = retStr.IndexOf('(');
        if (parenIdx > 0)
        {
            var retType = retStr[..parenIdx].Trim();
            // Pointers to structs (not basic types)
            if (retType.Contains('*') && !retType.StartsWith("const char")
                && retType != "void *" && retType != "const void *")
                return true;
            // References to non-ImVec types
            if (retType.Contains('&') && !retType.Contains("ImVec"))
                return true;
        }

        return f.Params.Any(p =>
        {
            var t = p.TypeStr.Trim();
            // Function pointers
            if (t.Contains("(*)")) return true;
            // Void pointers (callback userdata)
            if (t is "void *" or "const void *") return true;
            // va_list (Linux clang expands to __va_list_tag[1] etc.)
            if (t.Contains("va_list") || t.Contains("__va_list")) return true;
            // References to non-ImVec/non-basic types
            if (t.Contains('&') && !t.Contains("ImVec") && !IsBasicRef(t)) return true;
            return false;
        });
    }

    private static bool IsBasicRef(string typeStr)
    {
        // Allow const references to basic types
        var stripped = typeStr.Replace("const ", "").Replace("&", "").Trim();
        return stripped is "int" or "float" or "double" or "bool" or "char"
            or "unsigned int" or "size_t";
    }

    private bool IsOutputParam(ClangParam p, int floatArraySize)
    {
        var typeStr = p.TypeStr.Trim();
        if (typeStr == "const char *") return false;
        if (typeStr == "float *" && floatArraySize > 0 && FloatArrayParamNames.Contains(p.Name))
            return true; // Float array is always output
        return typeStr is "bool *" or "int *" or "float *" or "double *" or "unsigned int *";
    }

    private static int DetectFloatArraySize(string funcName)
    {
        // ColorEdit4 → 4, DragFloat2 → 2, SliderFloat3 → 3, etc.
        if (funcName.Length > 0 && char.IsDigit(funcName[^1]))
        {
            var n = funcName[^1] - '0';
            if (n >= 2 && n <= 4) return n;
        }
        return 0;
    }

    private static string MakeOverloadName(Funcs f)
    {
        var baseName = FunctionRenames.GetValueOrDefault(f.Name, Pipeline.ToSnakeCase(f.Name));
        var suffixes = f.Params.Select(p => TypeToSuffix(p.TypeStr.Trim()).ToLower());
        return $"{baseName}_{string.Join("_", suffixes)}";
    }

    private static string TypeToSuffix(string typeStr) => typeStr switch
    {
        "const char *" => "Str",
        "int" or "int32_t" => "Int",
        "float" => "Float",
        "double" => "Double",
        "bool" => "Bool",
        "unsigned int" or "uint32_t" => "Uint",
        _ when typeStr.Contains("ImVec2") => "Vec2",
        _ when typeStr.Contains("ImVec4") => "Vec4",
        _ when typeStr.Contains("*") => "Ptr",
        _ => "X"
    };

    // ===== Skip declarations =====

    /// <summary>
    /// Reason-by-name for items in SkipFunctions (explicit skip in BuildSpec)
    /// </summary>
    private static readonly Dictionary<string, string> SkipReasons = new()
    {
        // Context/internal management
        ["GetIO"] = "internal: IO struct managed by framework",
        ["GetPlatformIO"] = "internal: platform IO managed by framework",
        ["GetStyle"] = "internal: style struct access not exposed",
        ["GetDrawData"] = "internal: draw data managed by render pipeline",
        ["GetCurrentContext"] = "internal: context managed by framework",
        ["SetCurrentContext"] = "internal: context managed by framework",
        ["CreateContext"] = "internal: context managed by framework",
        ["DestroyContext"] = "internal: context managed by framework",
        ["NewFrame"] = "internal: called by imgui.new_frame wrapper",
        ["Render"] = "internal: called by imgui.render wrapper",
        ["EndFrame"] = "internal: called by imgui.render wrapper",
        ["GetMainViewport"] = "internal: viewport managed by framework",
        ["SetAllocatorFunctions"] = "internal: allocator managed by framework",
        ["GetAllocatorFunctions"] = "internal: allocator managed by framework",
        ["MemAlloc"] = "internal: use Lua memory management",
        ["MemFree"] = "internal: use Lua memory management",
        ["GetStateStorage"] = "internal: state storage not exposed",
        ["SetStateStorage"] = "internal: state storage not exposed",
        ["SaveIniSettingsToMemory"] = "internal: ini management not exposed",
        ["LoadIniSettingsFromMemory"] = "internal: ini management not exposed",
        // Draw list / font
        ["GetWindowDrawList"] = "draw list API: complex pointer type, not exposed",
        ["GetBackgroundDrawList"] = "draw list API: complex pointer type, not exposed",
        ["GetForegroundDrawList"] = "draw list API: complex pointer type, not exposed",
        ["GetFont"] = "font API: complex pointer type, not exposed",
        ["GetFontBaked"] = "font API: complex pointer type, not exposed",
        ["PushFont"] = "font API: font pointers not exposed",
        ["PopFont"] = "font API: font pointers not exposed",
        // Texture / image (requires ImTextureID)
        ["Image"] = "ImTextureID: texture handle binding not implemented",
        ["ImageWithBg"] = "ImTextureID: texture handle binding not implemented",
        ["ImageButton"] = "ImTextureID: texture handle binding not implemented",
        // Input text (callback-based)
        ["InputText"] = "callback: requires ImGuiInputTextCallback, complex binding",
        ["InputTextMultiline"] = "callback: requires ImGuiInputTextCallback",
        ["InputTextWithHint"] = "callback: requires ImGuiInputTextCallback",
        // Complex widget APIs
        ["ColorPicker4"] = "complex: many params, float array + callback",
        ["ColorConvertRGBtoHSV"] = "output pointers: use Lua math instead",
        ["ColorConvertHSVtoRGB"] = "output pointers: use Lua math instead",
        ["ListBox"] = "callback/array overloads: complex binding",
        ["Combo"] = "callback/array overloads: complex binding",
        ["PlotLines"] = "callback/array overloads: complex binding",
        ["PlotHistogram"] = "callback/array overloads: complex binding",
        // Multi-select
        ["BeginMultiSelect"] = "multi-select API: complex pointer return type",
        ["EndMultiSelect"] = "multi-select API: complex pointer return type",
        ["SetNextItemSelectionUserData"] = "multi-select API: selection data not exposed",
        // Style
        ["ShowStyleEditor"] = "style editor: debug tool, not needed in production",
        ["StyleColorsDark"] = "style: managed by framework setup",
        ["StyleColorsLight"] = "style: managed by framework setup",
        ["StyleColorsClassic"] = "style: managed by framework setup",
        // Constraints / shortcuts
        ["SetNextWindowSizeConstraints"] = "callback: requires custom resize callback",
        ["Shortcut"] = "shortcut API: ImGuiKeyChord binding not implemented",
        ["SetNextItemShortcut"] = "shortcut API: ImGuiKeyChord binding not implemented",
        // Mouse
        ["IsMousePosValid"] = "pointer param: optional ImVec2* not supported",
        // Debug
        ["DebugLog"] = "internal: debug logging not exposed",
        ["DebugLogV"] = "varargs: internal debug logging",
    };

    /// <summary>
    /// Reasons for functions filtered by IsVararg/HasUnsupportedParam
    /// </summary>
    private static readonly Dictionary<string, string> DynamicSkipReasons = new()
    {
        // varargs format functions
        ["Text"] = "varargs: Lua has string.format",
        ["TextV"] = "varargs: va_list variant",
        ["TextColored"] = "varargs: Lua has string.format",
        ["TextColoredV"] = "varargs: va_list variant",
        ["TextDisabled"] = "varargs: Lua has string.format",
        ["TextDisabledV"] = "varargs: va_list variant",
        ["TextWrapped"] = "varargs: Lua has string.format",
        ["TextWrappedV"] = "varargs: va_list variant",
        ["BulletText"] = "varargs: Lua has string.format",
        ["BulletTextV"] = "varargs: va_list variant",
        ["LabelText"] = "varargs: Lua has string.format",
        ["LabelTextV"] = "varargs: va_list variant",
        ["SetTooltip"] = "varargs: Lua has string.format",
        ["SetTooltipV"] = "varargs: va_list variant",
        ["SetItemTooltip"] = "varargs: Lua has string.format",
        ["SetItemTooltipV"] = "varargs: va_list variant",
        ["LogText"] = "varargs: Lua has string.format",
        ["LogTextV"] = "varargs: va_list variant",
        ["TreeNodeV"] = "varargs: va_list variant of TreeNode",
        ["TreeNodeExV"] = "varargs: va_list variant of TreeNodeEx",
        // void* / generic scalar
        ["DragScalar"] = "void* data: type-specific DragFloat/DragInt already bound",
        ["DragScalarN"] = "void* data: type-specific variants already bound",
        ["SliderScalar"] = "void* data: type-specific SliderFloat/SliderInt already bound",
        ["SliderScalarN"] = "void* data: type-specific variants already bound",
        ["VSliderScalar"] = "void* data: type-specific VSliderFloat/VSliderInt already bound",
        ["InputScalar"] = "void* data: type-specific InputFloat/InputInt already bound",
        ["InputScalarN"] = "void* data: type-specific variants already bound",
        // Complex return types
        ["AcceptDragDropPayload"] = "pointer return: ImGuiPayload* not exposed",
        ["GetDragDropPayload"] = "pointer return: ImGuiPayload* not exposed",
        ["SetDragDropPayload"] = "void* data: payload data binding not implemented",
        ["TableGetSortSpecs"] = "pointer return: ImGuiTableSortSpecs* not exposed",
        ["GetDrawListSharedData"] = "pointer return: internal shared data",
    };

    SkipReport IModule.CollectSkips(TypeRegistry reg)
    {
        var funcs = reg.AllDecls.OfType<Funcs>()
            .Where(f => f.Namespace == "ImGui")
            .ToList();

        // Check each individual overload (not just unique names)
        var skipFuncs = new List<SkipEntry>();
        foreach (var f in funcs)
        {
            // Same filters as BuildSpec — if this overload passes, it's bound
            if (!SkipFunctions.Contains(f.Name) && !IsVararg(f) && !HasUnsupportedParam(f))
                continue;
            var reason = SkipReasons.GetValueOrDefault(f.Name)
                ?? DynamicSkipReasons.GetValueOrDefault(f.Name)
                ?? "unsupported parameter or return type";
            skipFuncs.Add(new SkipEntry(f.Name, reason));
        }

        // Enum skips: track unique bound names, skip duplicates and non-ImGui enums
        var boundEnumNames = reg.AllDecls.OfType<Enums>()
            .Where(e => e.Name.StartsWith("ImGui"))
            .GroupBy(e => e.Name).Select(g => g.First())
            .Select(e => e.Name).ToHashSet();
        var seenEnumNames = new HashSet<string>();
        var skipEnums = new List<SkipEntry>();
        foreach (var e in reg.OwnEnums)
        {
            if (boundEnumNames.Contains(e.Name) && seenEnumNames.Add(e.Name)) continue;
            var reason = e.Name.StartsWith("ImGui")
                ? "duplicate enum declaration"
                : "non-ImGui enum: internal draw/font/texture type";
            skipEnums.Add(new SkipEntry(e.Name, reason));
        }

        return new SkipReport(ModuleName, skipFuncs, [], skipEnums);
    }

    private EnumBinding ConvertEnum(Enums e)
    {
        var fieldName = StripImGuiPrefix(e.Name);
        var luaName = $"imgui.{fieldName}";
        var next = 0;
        var items = e.Items
            .Where(i => !i.Name.StartsWith("_"))
            .Select(i =>
            {
                int? val = i.Value != null && int.TryParse(i.Value, out var v) ? v : null;
                var resolvedVal = val ?? next;
                next = resolvedVal + 1;
                var itemName = Pipeline.ToUpperSnakeCase(StripEnumItemPrefix(i.Name, e.Name));
                return new EnumItemBinding(itemName, i.Name, resolvedVal);
            }).ToList();

        return new EnumBinding(e.Name, luaName, fieldName, items, null);
    }

    private static string StripImGuiPrefix(string name)
    {
        if (name.StartsWith("ImGui"))
            name = name[5..]; // Strip "ImGui"
        return name.TrimEnd('_');
    }

    private static string StripEnumItemPrefix(string itemName, string enumName)
    {
        // ImGuiWindowFlags_NoTitleBar → "NoTitleBar"
        if (itemName.StartsWith(enumName))
            return itemName[enumName.Length..];
        return itemName;
    }
}
