namespace Generator.WebIdl;

/// <summary>
/// WebIDL IR → ModuleSpec 変換。
/// 既存の CBindingGen / LuaCatsGen をそのまま再利用する。
/// </summary>
public static class WebIdlToSpec
{
    public static ModuleSpec Convert(IdlFile file, string moduleName, string? extraCCode = null,
        string? idlBasePath = null)
    {
        var prefix = file.ExtAttrs.GetValueOrDefault("Prefix", "");
        var cIncludeRaw = file.ExtAttrs.GetValueOrDefault("CInclude", "");
        // 複数 CInclude: カンマ分割
        var includes = string.IsNullOrEmpty(cIncludeRaw)
            ? new List<string>()
            : cIncludeRaw.Split(',').Select(s => s.Trim()).Where(s => s.Length > 0).ToList();

        var funcNaming = file.ExtAttrs.GetValueOrDefault("FuncNaming", "");
        var isPascalCase = funcNaming == "PascalCase";

        // enum/dictionary/interface/callback 名を収集 (型参照解決用)
        var enumNames = file.Enums.Select(e => e.CName).ToHashSet();
        var dictNames = file.Dictionaries.Select(d => d.CName).ToHashSet();
        var ifaceNames = file.Interfaces.Select(i => i.CName).ToHashSet();
        var callbackNames = file.Callbacks.Select(c => c.CName).ToHashSet();

        // ValueStruct 名を収集
        var valueStructNames = file.Dictionaries
            .Where(d => HasFlag(d.ExtAttrs, "ValueStruct"))
            .Select(d => d.CName).ToHashSet();

        // HandleType 名を収集
        var handleTypeNames = file.Dictionaries
            .Where(d => HasFlag(d.ExtAttrs, "HandleType"))
            .Select(d => d.CName).ToHashSet();

        // Callback 型をビルド
        var callbackTypes = new Dictionary<string, BindingType.Callback>();
        var persistentCallbacks = new HashSet<string>();
        foreach (var cb in file.Callbacks)
        {
            var cbParams = cb.Params.Select(p =>
                (p.Name, ResolveType(p.Type))).ToList();
            var cbRet = ResolveType(cb.ReturnType);
            callbackTypes[cb.CName] = new BindingType.Callback(cbParams, cbRet);
            if (HasFlag(cb.ExtAttrs, "Persistent"))
                persistentCallbacks.Add(cb.CName);
        }

        BindingType ResolveType(IdlType t) => MapType(t, moduleName, prefix,
            enumNames, dictNames, ifaceNames, callbackNames, callbackTypes,
            valueStructNames, handleTypeNames, file);

        // namespace → funcs
        var funcs = new List<FuncBinding>();
        var arrayAdapters = new List<ArrayAdapterBinding>();
        if (file.Namespace != null)
        {
            foreach (var op in file.Namespace.Operations)
            {
                if (HasFlag(op.ExtAttrs, "Ignore")) continue;

                // ArrayAdapter
                if (HasFlag(op.ExtAttrs, "ArrayAdapter"))
                {
                    var countFunc = op.ExtAttrs!["CountFunc"];
                    var fillCName = prefix + op.Name;
                    var luaName = isPascalCase
                        ? Pipeline.ToSnakeCase(op.Name)
                        : op.Name;
                    var inputParams = op.Params.Select(p =>
                        new ParamBinding(p.Name, ResolveType(p.Type))).ToList();
                    arrayAdapters.Add(new ArrayAdapterBinding(
                        luaName, countFunc, fillCName, inputParams, ResolveType(op.ReturnType)));
                    continue;
                }

                var cName = isPascalCase
                    ? prefix + op.Name
                    : prefix + op.Name;
                var funcLuaName = isPascalCase
                    ? Pipeline.ToSnakeCase(op.Name)
                    : op.Name;

                // OutputParams
                var outputParamNames = new HashSet<string>();
                if (op.ExtAttrs != null && op.ExtAttrs.TryGetValue("OutputParams", out var outputRaw))
                    foreach (var p in outputRaw.Split(','))
                        outputParamNames.Add(p.Trim());

                // Build params with callback bridge and void* context removal
                var parms = new List<ParamBinding>();
                var skipNextVoidPtr = false;
                foreach (var p in op.Params)
                {
                    if (skipNextVoidPtr && p.Type.Name == "VoidPtr")
                    {
                        skipNextVoidPtr = false;
                        continue;
                    }
                    skipNextVoidPtr = false;

                    var pt = ResolveType(p.Type);

                    // Callback parameter → set CallbackBridge and skip next void* context
                    if (callbackNames.Contains(p.Type.Name))
                    {
                        var mode = persistentCallbacks.Contains(p.Type.Name)
                            ? CallbackBridgeMode.Persistent
                            : CallbackBridgeMode.Immediate;
                        parms.Add(new ParamBinding(p.Name, pt,
                            IsOptional: mode == CallbackBridgeMode.Persistent,
                            CallbackBridge: mode));
                        skipNextVoidPtr = true;
                        continue;
                    }

                    // Struct params → ConstPtr (except HandleType)
                    pt = PromoteStructParam(pt, handleTypeNames);
                    var isOutput = outputParamNames.Contains(p.Name);
                    parms.Add(new ParamBinding(p.Name, pt, IsOutput: isOutput));
                }

                // PostCallPatch
                List<PostCallPatch>? patches = null;
                if (op.ExtAttrs != null && op.ExtAttrs.TryGetValue("PostCallPatch", out var patchRaw))
                {
                    patches = patchRaw.Split(',').Select(entry =>
                    {
                        var parts = entry.Split(':');
                        return new PostCallPatch(parts[0].Trim(), parts[1].Trim());
                    }).ToList();
                }

                funcs.Add(new FuncBinding(cName, funcLuaName, parms, ResolveType(op.ReturnType), null,
                    PostCallPatches: patches));
            }
        }

        // enum → EnumBinding
        var enums = file.Enums.Select(e => ConvertEnum(e, moduleName, prefix)).ToList();

        // dictionary → StructBinding (ValueStruct/HandleType は StructBinding を生成しない)
        var structs = new List<StructBinding>();
        foreach (var d in file.Dictionaries)
        {
            if (HasFlag(d.ExtAttrs, "ValueStruct")) continue; // ValueStruct は型解決で処理
            structs.Add(ConvertDict(d, moduleName, prefix, ResolveType, file, idlBasePath));
        }

        // interface → OpaqueTypeBinding
        var opaqueTypes = file.Interfaces.Select(i => ConvertInterface(i, moduleName, prefix, ResolveType)).ToList();

        // EventAdapter
        var eventAdapters = file.EventAdapters.Select(ev => ConvertEventAdapter(ev, prefix, ResolveType)).ToList();

        // ExtraLuaReg
        var extraLuaRegs = ParseKvList(file.ExtAttrs.GetValueOrDefault("ExtraLuaReg", ""));

        // ExtraLuaFunc
        var extraLuaFuncs = ParseExtraLuaFuncs(
            file.ExtAttrs.GetValueOrDefault("ExtraLuaFunc", ""),
            moduleName, prefix, enumNames, dictNames, ifaceNames,
            callbackNames, callbackTypes, valueStructNames, handleTypeNames, file);

        return new ModuleSpec(
            ModuleName: moduleName,
            Prefix: prefix,
            CIncludes: includes,
            ExtraCCode: extraCCode,
            Structs: structs,
            Funcs: funcs,
            Enums: enums,
            ExtraLuaRegs: extraLuaRegs,
            OpaqueTypes: opaqueTypes.Count > 0 ? opaqueTypes : null,
            ExtraLuaFuncs: extraLuaFuncs.Count > 0 ? extraLuaFuncs : null,
            ArrayAdapters: arrayAdapters.Count > 0 ? arrayAdapters : null,
            EventAdapters: eventAdapters.Count > 0 ? eventAdapters : null
        );
    }

    private static bool HasFlag(Dictionary<string, string>? attrs, string key)
        => attrs != null && attrs.ContainsKey(key);

    /// <summary>
    /// C API 規約: struct パラメータは const ポインタ渡し。
    /// IDL では値型で記述するが、Converter で ConstPtr(Struct) に昇格する。
    /// HandleType は値渡しなので昇格しない。
    /// </summary>
    private static BindingType PromoteStructParam(BindingType t, HashSet<string> handleTypeNames) => t switch
    {
        BindingType.Struct s when !handleTypeNames.Contains(s.CName) => new BindingType.ConstPtr(t),
        _ => t
    };

    /// <summary>
    /// "key1:val1,key2:val2" → [(key1, val1), (key2, val2)]
    /// </summary>
    private static List<(string LuaName, string CFunc)> ParseKvList(string raw)
    {
        if (string.IsNullOrEmpty(raw)) return [];
        return raw.Split(',')
            .Select(entry =>
            {
                var parts = entry.Split(':');
                return (parts[0].Trim(), parts[1].Trim());
            }).ToList();
    }

    /// <summary>
    /// "funcName:paramType:returnType,..." → FuncBinding リスト (LuaCATS アノテーション用)
    /// マルチパラムは "+" 区切り: "funcName:type1+type2+type3?:returnType"
    /// "?" サフィックスは optional パラメータ
    /// </summary>
    private static List<FuncBinding> ParseExtraLuaFuncs(string raw,
        string moduleName, string prefix,
        HashSet<string> enumNames, HashSet<string> dictNames,
        HashSet<string>? ifaceNames = null,
        HashSet<string>? callbackNames = null,
        Dictionary<string, BindingType.Callback>? callbackTypes = null,
        HashSet<string>? valueStructNames = null,
        HashSet<string>? handleTypeNames = null,
        IdlFile? file = null)
    {
        if (string.IsNullOrEmpty(raw)) return [];
        ifaceNames ??= [];
        callbackNames ??= [];
        callbackTypes ??= [];
        valueStructNames ??= [];
        handleTypeNames ??= [];
        return raw.Split(',')
            .Select(entry =>
            {
                var parts = entry.Split(':');
                var luaName = parts[0].Trim();
                var paramTypesRaw = parts[1].Trim();
                var returnTypeName = parts[2].Trim();
                var returnType = MapType(new IdlType(returnTypeName), moduleName, prefix,
                    enumNames, dictNames, ifaceNames, callbackNames, callbackTypes,
                    valueStructNames, handleTypeNames, file);

                var parms = new List<ParamBinding>();
                if (paramTypesRaw != "void")
                {
                    var paramParts = paramTypesRaw.Split('+');
                    for (var i = 0; i < paramParts.Length; i++)
                    {
                        var raw2 = paramParts[i].Trim();
                        var isOptional = raw2.EndsWith('?');
                        if (isOptional) raw2 = raw2[..^1];
                        var paramType = MapType(new IdlType(raw2), moduleName, prefix,
                            enumNames, dictNames, ifaceNames, callbackNames, callbackTypes,
                            valueStructNames, handleTypeNames, file);
                        var paramName = i == 0 && paramParts.Length == 1 ? "desc" : $"p{i + 1}";
                        parms.Add(new ParamBinding(paramName, paramType, IsOptional: isOptional));
                    }
                }

                return new FuncBinding(
                    CName: $"l_{prefix}{luaName}",
                    LuaName: luaName,
                    Params: parms,
                    ReturnType: returnType,
                    SourceLink: null
                );
            }).ToList();
    }

    private static EnumBinding ConvertEnum(IdlEnum e, string moduleName, string prefix)
    {
        var stripped = Pipeline.StripPrefix(e.CName, prefix);
        var pascalName = Pipeline.ToPascalCase(stripped);
        var luaName = $"{moduleName}.{pascalName}";

        var enumItemStyle = e.ExtAttrs?.GetValueOrDefault("EnumItemStyle", null);

        var items = e.Values.Select(v =>
        {
            string itemLuaName;
            if (enumItemStyle == "CamelCase")
            {
                // b2_staticBody → strip "b2_" → "staticBody" → "STATIC_BODY"
                var itemStripped = Pipeline.StripPrefix(v.Name, prefix + "_");
                itemLuaName = Pipeline.ToUpperSnakeCase(itemStripped);
            }
            else
            {
                itemLuaName = Pipeline.EnumItemName(v.Name, e.CName, prefix).ToUpper();
            }
            return new EnumItemBinding(itemLuaName, v.Name, v.Value);
        }).ToList();
        return new EnumBinding(e.CName, luaName, pascalName, items, null);
    }

    private static StructBinding ConvertDict(IdlDictionary d, string moduleName, string prefix,
        Func<IdlType, BindingType> resolveType, IdlFile? file = null, string? idlBasePath = null)
    {
        var stripped = Pipeline.StripPrefix(d.CName, prefix);
        var pascalName = Pipeline.ToPascalCase(Pipeline.StripTypeSuffix(stripped));
        var metatable = $"{moduleName}.{pascalName}";
        var camelCase = HasFlag(d.ExtAttrs, "CamelCase");
        var isHandleType = HasFlag(d.ExtAttrs, "HandleType");

        // Field filtering: skip [Ignore] fields
        var fields = d.Fields
            .Where(f => !HasFlag(f.ExtAttrs, "Ignore"))
            .Select(f => new FieldBinding(
                f.Name,
                camelCase ? Pipeline.ToSnakeCase(f.Name) : f.Name,
                resolveType(f.Type)
            )).ToList();

        var hasMeta = HasFlag(d.ExtAttrs, "HasMetamethods");
        var allowStringInit = HasFlag(d.ExtAttrs, "AllowStringInit");

        // MapFieldName: "init_cb:init,frame_cb:frame,..." → フィールド名変換
        var mapFieldName = d.ExtAttrs?.GetValueOrDefault("MapFieldName", "") ?? "";
        if (!string.IsNullOrEmpty(mapFieldName))
        {
            var mapping = mapFieldName.Split(',')
                .Select(e =>
                {
                    var parts = e.Split(':');
                    return (From: parts[0].Trim(), To: parts[1].Trim());
                })
                .ToDictionary(e => e.From, e => e.To);
            fields = fields.Select(f =>
                mapping.TryGetValue(f.CName, out var luaName)
                    ? f with { LuaName = luaName }
                    : f
            ).ToList();
        }

        // Property bindings from [Property_xxx="path:type"] ExtAttrs
        List<PropertyBinding>? properties = null;
        if (d.ExtAttrs != null && idlBasePath != null)
        {
            foreach (var (key, value) in d.ExtAttrs)
            {
                if (!key.StartsWith("Property_")) continue;
                var propName = key["Property_".Length..];
                // value format: "relative/path.c:TypeName"
                var colonIdx = value.LastIndexOf(':');
                var relPath = colonIdx >= 0 ? value[..colonIdx] : value;
                var typeName = colonIdx >= 0 ? value[(colonIdx + 1)..] : "";
                var filePath = Path.Combine(idlBasePath, relPath);
                if (File.Exists(filePath))
                {
                    var content = File.ReadAllText(filePath);
                    var parts = content.Split("---SETTER---");
                    var getter = parts[0].TrimEnd();
                    var setter = parts.Length > 1 ? parts[1].TrimStart() : null;
                    var propType = string.IsNullOrEmpty(typeName)
                        ? (BindingType)new BindingType.Void()
                        : resolveType(new IdlType(typeName));
                    // Array property: wrap in FixedArray(type, 0) to signal variable-length
                    var arrayType = propType is BindingType.ValueStruct vs
                        ? (BindingType)new BindingType.ValueStructArray(vs.CTypeName, vs.LuaCatsType,
                            vs.Fields)
                        : new BindingType.FixedArray(propType, 0);
                    properties ??= [];
                    properties.Add(new PropertyBinding(propName, arrayType, getter, setter));
                }
            }
        }

        return new StructBinding(d.CName, pascalName, metatable, hasMeta, fields, null,
            IsHandleType: isHandleType, AllowStringInit: allowStringInit,
            Properties: properties);
    }

    private static OpaqueTypeBinding ConvertInterface(IdlInterface iface, string moduleName, string prefix,
        Func<IdlType, BindingType> resolveType)
    {
        var stripped = Pipeline.StripPrefix(iface.CName, prefix);
        var pascalName = Pipeline.ToPascalCase(Pipeline.StripTypeSuffix(stripped));
        var metatable = $"{moduleName}.{pascalName}";

        var initFunc = iface.ExtAttrs?.GetValueOrDefault("InitFunc", null);
        var uninitFunc = iface.ExtAttrs?.GetValueOrDefault("UninitFunc", null);
        var configType = iface.ExtAttrs?.GetValueOrDefault("ConfigType", null);
        var configInitFunc = iface.ExtAttrs?.GetValueOrDefault("ConfigInitFunc", null);

        // Dependency: "engine:1" → DependencyBinding(ConstructorArgIndex=1, UservalueSlot=1, Name="engine")
        List<DependencyBinding>? deps = null;
        var depRaw = iface.ExtAttrs?.GetValueOrDefault("Dependency", null);
        if (!string.IsNullOrEmpty(depRaw))
        {
            deps = depRaw.Split(',').Select(entry =>
            {
                var parts = entry.Split(':');
                var name = parts[0].Trim();
                var argIdx = int.Parse(parts[1].Trim());
                return new DependencyBinding(argIdx, argIdx, name);
            }).ToList();
        }

        var methods = iface.Methods.Select(m =>
        {
            var cName = $"{iface.CName}_{m.Name}";
            var parms = m.Params.Select(p => new ParamBinding(p.Name, resolveType(p.Type))).ToList();
            return new MethodBinding(cName, m.Name, parms, resolveType(m.ReturnType), null);
        }).ToList();

        return new OpaqueTypeBinding(
            iface.CName, pascalName, metatable, metatable,
            initFunc, uninitFunc, configType, configInitFunc,
            methods, null, deps);
    }

    private static EventAdapterBinding ConvertEventAdapter(IdlEventAdapter ev, string prefix,
        Func<IdlType, BindingType> resolveType)
    {
        // CFunc: IDL で明示指定されていればそれを使用、なければ prefix + PascalCase(LuaName)
        var cFuncName = ev.CFunc ?? prefix + Pipeline.ToPascalCase(ev.LuaName);

        var inputParams = ev.Params.Select(p =>
            new ParamBinding(p.Name, resolveType(p.Type))).ToList();

        var arrayFields = ev.Arrays.Select(a =>
        {
            var elementFields = a.Fields.Select(f =>
                new EventElementField(f.LuaName, f.CAccessor, resolveType(f.Type))).ToList();
            return new EventArrayField(a.LuaFieldName, a.CArrayAccessor, a.CCountAccessor, elementFields);
        }).ToList();

        return new EventAdapterBinding(ev.LuaName, cFuncName, ev.CReturnType, inputParams, arrayFields);
    }

    /// <summary>
    /// ValueStruct dictionary の field 定義から ValueStruct BindingType を構築する。
    /// [Nested="p:x+y,q:c+s"] から NestedFields を生成。
    /// 明示 field は ScalarField として処理。
    /// </summary>
    private static BindingType BuildValueStructType(IdlDictionary d, bool readOnly)
    {
        var vsFields = new List<BindingType.ValueStructField>();
        var hasNested = false;

        // Nested ExtAttr: "p:x+y,q:c+s"
        var nestedRaw = d.ExtAttrs?.GetValueOrDefault("Nested", null);
        if (!string.IsNullOrEmpty(nestedRaw))
        {
            hasNested = true;
            foreach (var group in nestedRaw.Split(','))
            {
                var parts = group.Split(':');
                var accessor = parts[0].Trim();
                var subs = parts[1].Split('+').Select(s => s.Trim()).ToList();
                vsFields.Add(new BindingType.NestedFields(accessor, subs));
            }
        }

        // Explicit fields (only if no Nested attr — fields serve as documentation for empty-body dicts)
        if (!hasNested)
        {
            foreach (var f in d.Fields)
            {
                vsFields.Add(new BindingType.ScalarField(f.Name));
            }
        }

        var luaCatsType = hasNested ? "number[][]" : "number[]";
        return new BindingType.ValueStruct(d.CName, luaCatsType, vsFields, Settable: !readOnly);
    }

    private static BindingType MapType(IdlType t, string moduleName, string prefix,
        HashSet<string> enumNames, HashSet<string> dictNames,
        HashSet<string>? ifaceNames = null,
        HashSet<string>? callbackNames = null,
        Dictionary<string, BindingType.Callback>? callbackTypes = null,
        HashSet<string>? valueStructNames = null,
        HashSet<string>? handleTypeNames = null,
        IdlFile? file = null)
    {
        ifaceNames ??= [];
        callbackNames ??= [];
        callbackTypes ??= [];
        valueStructNames ??= [];
        handleTypeNames ??= [];

        // FixedArray: type[N]
        if (t.ArrayLength.HasValue)
        {
            var inner = MapType(t with { ArrayLength = null }, moduleName, prefix,
                enumNames, dictNames, ifaceNames, callbackNames, callbackTypes,
                valueStructNames, handleTypeNames, file);
            return new BindingType.FixedArray(inner, t.ArrayLength.Value);
        }

        // Primitive types
        var result = t.Name switch
        {
            "void" => new BindingType.Void(),
            "unsigned long long" => (BindingType)new BindingType.UInt64(),
            "long long" => new BindingType.Int64(),
            "unsigned long" => new BindingType.UInt32(),
            "long" => new BindingType.Int(),
            "unsigned short" => new BindingType.Int(),
            "short" => new BindingType.Int(),
            "float" => new BindingType.Float(),
            "double" => new BindingType.Double(),
            "boolean" => new BindingType.Bool(),
            "byte" or "octet" => new BindingType.Int(),
            "DOMString" => new BindingType.Str(),
            "VoidPtr" => new BindingType.VoidPtr(),
            "ConstVoidPtr" => new BindingType.ConstPtr(new BindingType.Void()),
            "Size" => new BindingType.Size(),
            "Callback" => new BindingType.Callback([], new BindingType.Void()),
            _ => (BindingType?)null
        };

        if (result != null) return result;

        // Callback type reference
        if (callbackTypes.TryGetValue(t.Name, out var cbType))
            return cbType;

        // ValueStruct type reference
        if (valueStructNames.Contains(t.Name) && file != null)
        {
            var dict = file.Dictionaries.First(d => d.CName == t.Name);
            var readOnly = HasFlag(dict.ExtAttrs, "ReadOnly");
            return BuildValueStructType(dict, readOnly);
        }

        // HandleType type reference → same as Struct
        if (handleTypeNames.Contains(t.Name))
        {
            var stripped = Pipeline.StripPrefix(t.Name, prefix);
            var pascalName = Pipeline.ToPascalCase(Pipeline.StripTypeSuffix(stripped));
            var fullName = $"{moduleName}.{pascalName}";
            return new BindingType.Struct(t.Name, fullName, fullName);
        }

        // Enum reference
        if (enumNames.Contains(t.Name))
        {
            var stripped = Pipeline.StripPrefix(t.Name, prefix);
            var luaName = $"{moduleName}.{Pipeline.ToPascalCase(stripped)}";
            return new BindingType.Enum(t.Name, luaName);
        }

        // Dictionary (struct) reference
        if (dictNames.Contains(t.Name))
        {
            var stripped = Pipeline.StripPrefix(t.Name, prefix);
            var pascalName = Pipeline.ToPascalCase(Pipeline.StripTypeSuffix(stripped));
            var fullName = $"{moduleName}.{pascalName}";
            return new BindingType.Struct(t.Name, fullName, fullName);
        }

        // Interface (opaque type) reference
        if (ifaceNames.Contains(t.Name))
        {
            var stripped = Pipeline.StripPrefix(t.Name, prefix);
            var pascalName = Pipeline.ToPascalCase(Pipeline.StripTypeSuffix(stripped));
            var fullName = $"{moduleName}.{pascalName}";
            return new BindingType.Struct(t.Name, fullName, fullName);
        }

        // Cross-module struct reference (e.g. sg_environment from sokol.gfx)
        // Use the C name as-is and try to resolve module
        return ResolveExternalType(t.Name);
    }

    // クロスモジュール enum 型の既知リスト
    private static readonly HashSet<string> KnownExternalEnums =
    [
        // sokol_gfx.h
        "sg_backend", "sg_pixel_format", "sg_resource_state", "sg_index_type",
        "sg_image_type", "sg_image_sample_type", "sg_sampler_type",
        "sg_primitive_type", "sg_filter", "sg_wrap", "sg_border_color",
        "sg_vertex_format", "sg_vertex_step", "sg_uniform_type", "sg_uniform_layout",
        "sg_cull_mode", "sg_face_winding", "sg_compare_func", "sg_stencil_op",
        "sg_blend_factor", "sg_blend_op", "sg_color_mask", "sg_load_action",
        "sg_store_action", "sg_view_type", "sg_shader_stage",
        "sg_shader_attr_base_type", "sg_log_item",
        // sokol_app.h
        "sapp_event_type", "sapp_keycode", "sapp_mousebutton",
        "sapp_log_item",
        // sokol_audio.h
        "saudio_log_item",
    ];

    /// <summary>
    /// 他モジュールの型を解決する。prefix から所属モジュールを推定する。
    /// </summary>
    private static BindingType ResolveExternalType(string cName)
    {
        // Known prefix → module mappings
        var prefixMap = new Dictionary<string, (string Module, string Prefix)>
        {
            ["sg_"] = ("sokol.gfx", "sg_"),
            ["sapp_"] = ("sokol.app", "sapp_"),
            ["sglue_"] = ("sokol.glue", "sglue_"),
            ["stm_"] = ("sokol.time", "stm_"),
            ["saudio_"] = ("sokol.audio", "saudio_"),
            ["sgl_"] = ("sokol.gl", "sgl_"),
            ["sdtx_"] = ("sokol.debugtext", "sdtx_"),
            ["sshape_"] = ("sokol.shape", "sshape_"),
            ["simgui_"] = ("sokol.imgui", "simgui_"),
            ["ma_"] = ("miniaudio", "ma_"),
        };

        foreach (var (pre, (mod, _)) in prefixMap)
        {
            if (cName.StartsWith(pre))
            {
                var stripped = Pipeline.StripPrefix(cName, pre);
                var pascalName = Pipeline.ToPascalCase(Pipeline.StripTypeSuffix(stripped));

                // enum 型の場合
                if (KnownExternalEnums.Contains(cName))
                {
                    var luaName = $"{mod}.{pascalName}";
                    return new BindingType.Enum(cName, luaName);
                }

                var fullName = $"{mod}.{pascalName}";
                return new BindingType.Struct(cName, fullName, fullName);
            }
        }

        throw new NotSupportedException($"Unsupported WebIDL type: {cName}");
    }
}
