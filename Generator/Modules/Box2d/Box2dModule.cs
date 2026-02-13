namespace Generator.Modules.Box2d;

using Generator.ClangAst;

/// <summary>
/// Box2D v3 Lua バインディングモジュール
/// Clang AST パースで ~150 関数を自動生成 + ExtraCCode でイベント/配列/コールバック ラッパー
/// </summary>
public class Box2dModule : IModule
{
    public string ModuleName => "b2d";
    public string Prefix => "b2";

    // ===== Custom 型定義 (b2Vec2, b2Rot) =====

    /// <summary>b2Vec2 → Lua table {x, y}</summary>
    private static readonly BindingType B2Vec2Type = new BindingType.Custom(
        "b2Vec2", "number[]",
        InitCode: null,
        CheckCode:
            "    luaL_checktype(L, {idx}, LUA_TTABLE);\n" +
            "    b2Vec2 {name};\n" +
            "    lua_rawgeti(L, {idx}, 1); {name}.x = (float)lua_tonumber(L, -1); lua_pop(L, 1);\n" +
            "    lua_rawgeti(L, {idx}, 2); {name}.y = (float)lua_tonumber(L, -1); lua_pop(L, 1);",
        PushCode:
            "b2Vec2 _v = {value};\n" +
            "    lua_newtable(L);\n" +
            "    lua_pushnumber(L, _v.x); lua_rawseti(L, -2, 1);\n" +
            "    lua_pushnumber(L, _v.y); lua_rawseti(L, -2, 2);",
        SetCode:
            "luaL_checktype(L, 3, LUA_TTABLE);\n" +
            "            lua_rawgeti(L, 3, 1); self->{fieldName}.x = (float)lua_tonumber(L, -1); lua_pop(L, 1);\n" +
            "            lua_rawgeti(L, 3, 2); self->{fieldName}.y = (float)lua_tonumber(L, -1); lua_pop(L, 1)");

    /// <summary>b2CosSin → Lua table {cosine, sine}</summary>
    private static readonly BindingType B2CosSinType = new BindingType.Custom(
        "b2CosSin", "number[]",
        InitCode: null,
        CheckCode:
            "    luaL_checktype(L, {idx}, LUA_TTABLE);\n" +
            "    b2CosSin {name};\n" +
            "    lua_rawgeti(L, {idx}, 1); {name}.cosine = (float)lua_tonumber(L, -1); lua_pop(L, 1);\n" +
            "    lua_rawgeti(L, {idx}, 2); {name}.sine = (float)lua_tonumber(L, -1); lua_pop(L, 1);",
        PushCode:
            "b2CosSin _cs = {value};\n" +
            "    lua_newtable(L);\n" +
            "    lua_pushnumber(L, _cs.cosine); lua_rawseti(L, -2, 1);\n" +
            "    lua_pushnumber(L, _cs.sine); lua_rawseti(L, -2, 2);",
        SetCode: null);

    /// <summary>b2Rot → Lua table {c, s}</summary>
    private static readonly BindingType B2RotType = new BindingType.Custom(
        "b2Rot", "number[]",
        InitCode: null,
        CheckCode:
            "    luaL_checktype(L, {idx}, LUA_TTABLE);\n" +
            "    b2Rot {name};\n" +
            "    lua_rawgeti(L, {idx}, 1); {name}.c = (float)lua_tonumber(L, -1); lua_pop(L, 1);\n" +
            "    lua_rawgeti(L, {idx}, 2); {name}.s = (float)lua_tonumber(L, -1); lua_pop(L, 1);",
        PushCode:
            "b2Rot _r = {value};\n" +
            "    lua_newtable(L);\n" +
            "    lua_pushnumber(L, _r.c); lua_rawseti(L, -2, 1);\n" +
            "    lua_pushnumber(L, _r.s); lua_rawseti(L, -2, 2);",
        SetCode:
            "luaL_checktype(L, 3, LUA_TTABLE);\n" +
            "            lua_rawgeti(L, 3, 1); self->{fieldName}.c = (float)lua_tonumber(L, -1); lua_pop(L, 1);\n" +
            "            lua_rawgeti(L, 3, 2); self->{fieldName}.s = (float)lua_tonumber(L, -1); lua_pop(L, 1)");

    /// <summary>b2Transform → Lua table {{px,py},{c,s}}</summary>
    private static readonly BindingType B2TransformType = new BindingType.Custom(
        "b2Transform", "number[][]",
        InitCode: null,
        CheckCode:
            "    luaL_checktype(L, {idx}, LUA_TTABLE);\n" +
            "    b2Transform {name};\n" +
            "    lua_rawgeti(L, {idx}, 1); luaL_checktype(L, -1, LUA_TTABLE);\n" +
            "    lua_rawgeti(L, -1, 1); {name}.p.x = (float)lua_tonumber(L, -1); lua_pop(L, 1);\n" +
            "    lua_rawgeti(L, -1, 2); {name}.p.y = (float)lua_tonumber(L, -1); lua_pop(L, 1);\n" +
            "    lua_pop(L, 1);\n" +
            "    lua_rawgeti(L, {idx}, 2); luaL_checktype(L, -1, LUA_TTABLE);\n" +
            "    lua_rawgeti(L, -1, 1); {name}.q.c = (float)lua_tonumber(L, -1); lua_pop(L, 1);\n" +
            "    lua_rawgeti(L, -1, 2); {name}.q.s = (float)lua_tonumber(L, -1); lua_pop(L, 1);\n" +
            "    lua_pop(L, 1);",
        PushCode:
            "b2Transform _t = {value};\n" +
            "    lua_newtable(L);\n" +
            "    lua_newtable(L);\n" +
            "    lua_pushnumber(L, _t.p.x); lua_rawseti(L, -2, 1);\n" +
            "    lua_pushnumber(L, _t.p.y); lua_rawseti(L, -2, 2);\n" +
            "    lua_rawseti(L, -2, 1);\n" +
            "    lua_newtable(L);\n" +
            "    lua_pushnumber(L, _t.q.c); lua_rawseti(L, -2, 1);\n" +
            "    lua_pushnumber(L, _t.q.s); lua_rawseti(L, -2, 2);\n" +
            "    lua_rawseti(L, -2, 2);",
        SetCode: null);

    /// <summary>b2AABB → Lua table {{lx,ly},{ux,uy}}</summary>
    private static readonly BindingType B2AABBType = new BindingType.Custom(
        "b2AABB", "number[][]",
        InitCode: null,
        CheckCode:
            "    luaL_checktype(L, {idx}, LUA_TTABLE);\n" +
            "    b2AABB {name};\n" +
            "    lua_rawgeti(L, {idx}, 1); luaL_checktype(L, -1, LUA_TTABLE);\n" +
            "    lua_rawgeti(L, -1, 1); {name}.lowerBound.x = (float)lua_tonumber(L, -1); lua_pop(L, 1);\n" +
            "    lua_rawgeti(L, -1, 2); {name}.lowerBound.y = (float)lua_tonumber(L, -1); lua_pop(L, 1);\n" +
            "    lua_pop(L, 1);\n" +
            "    lua_rawgeti(L, {idx}, 2); luaL_checktype(L, -1, LUA_TTABLE);\n" +
            "    lua_rawgeti(L, -1, 1); {name}.upperBound.x = (float)lua_tonumber(L, -1); lua_pop(L, 1);\n" +
            "    lua_rawgeti(L, -1, 2); {name}.upperBound.y = (float)lua_tonumber(L, -1); lua_pop(L, 1);\n" +
            "    lua_pop(L, 1);",
        PushCode:
            "b2AABB _a = {value};\n" +
            "    lua_newtable(L);\n" +
            "    lua_newtable(L);\n" +
            "    lua_pushnumber(L, _a.lowerBound.x); lua_rawseti(L, -2, 1);\n" +
            "    lua_pushnumber(L, _a.lowerBound.y); lua_rawseti(L, -2, 2);\n" +
            "    lua_rawseti(L, -2, 1);\n" +
            "    lua_newtable(L);\n" +
            "    lua_pushnumber(L, _a.upperBound.x); lua_rawseti(L, -2, 1);\n" +
            "    lua_pushnumber(L, _a.upperBound.y); lua_rawseti(L, -2, 2);\n" +
            "    lua_rawseti(L, -2, 2);",
        SetCode: null);

    // ===== Handle 型 (struct userdata) =====

    private BindingType HandleType(string cName) =>
        new BindingType.Struct(cName, $"{ModuleName}.{Pipeline.ToPascalCase(Pipeline.StripPrefix(cName, Prefix))}",
            $"{ModuleName}.{Pipeline.ToPascalCase(Pipeline.StripPrefix(cName, Prefix))}");

    // ===== スキップ対象 =====

    private static readonly HashSet<string> SkipFuncs =
    [
        // DebugDraw
        "b2World_Draw", "b2DefaultDebugDraw",
        // void* UserData
        "b2World_SetUserData", "b2World_GetUserData",
        "b2Body_SetUserData", "b2Body_GetUserData",
        "b2Shape_SetUserData", "b2Shape_GetUserData",
        "b2Joint_SetUserData", "b2Joint_GetUserData",
        // Memory dump
        "b2World_DumpMemoryStats",
        // Callback setters (need custom wrappers or skip)
        "b2World_SetCustomFilterCallback", "b2World_SetPreSolveCallback",
        "b2World_SetFrictionCallback", "b2World_SetRestitutionCallback",
        // Query functions (need Lua callback wrappers → ExtraCCode)
        "b2World_OverlapAABB", "b2World_OverlapShape",
        "b2World_CastRay", "b2World_CastShape",
        "b2World_CastMover", "b2World_CollideMover",
        // Array output functions → ExtraCCode
        "b2Body_GetShapes", "b2Body_GetJoints", "b2Body_GetContactData",
        "b2Shape_GetContactData", "b2Shape_GetSensorOverlaps",
        "b2Chain_GetSegments",
        // Output param functions → ExtraCCode
        "b2Joint_GetConstraintTuning",
        // Event functions (return array structs) → ExtraCCode
        "b2World_GetBodyEvents", "b2World_GetSensorEvents", "b2World_GetContactEvents",
        // Allocator / Assert
        "b2SetAllocator", "b2SetAssertFcn",
        // Internal / low-level
        "b2World_EnableSpeculative",
        // Store/Load id serialization
        "b2StoreWorldId", "b2LoadWorldId",
        "b2StoreBodyId", "b2LoadBodyId",
        "b2StoreShapeId", "b2LoadShapeId",
        "b2StoreChainId", "b2LoadChainId",
        "b2StoreJointId", "b2LoadJointId",
        // Timer (output pointer param)
        "b2GetMillisecondsAndReset",
    ];

    private static readonly string[] SkipFuncPrefixes =
    [
        // DynamicTree is internal broad-phase API
        "b2DynamicTree_",
    ];

    private static readonly HashSet<string> SkipStructs =
    [
        // Math types → Custom
        "b2Vec2", "b2Rot", "b2Transform", "b2AABB", "b2CosSin", "b2Mat22", "b2Plane",
        // Event container structs (used in ExtraCCode only)
        "b2BodyEvents", "b2SensorEvents", "b2ContactEvents",
        "b2SensorBeginTouchEvent", "b2SensorEndTouchEvent",
        "b2ContactBeginTouchEvent", "b2ContactEndTouchEvent", "b2ContactHitEvent",
        "b2BodyMoveEvent",
        // DebugDraw
        "b2DebugDraw", "b2HexColor",
        // Internal
        "b2Version", "b2Counters", "b2Profile", "b2TreeStats",
        // Collision internals
        "b2ManifoldPoint", "b2Manifold", "b2ContactData",
        "b2SimplexCache", "b2Simplex", "b2SimplexVertex",
        "b2DistanceInput", "b2DistanceOutput",
        "b2SegmentDistanceResult",
        "b2Sweep", "b2TOIInput", "b2TOIOutput",
        "b2ShapeCastPairInput",
        "b2CollisionPlane", "b2PlaneSolverResult", "b2PlaneResult",
        // Dynamic tree
        "b2DynamicTree",
    ];

    private static readonly HashSet<string> SkipEnums =
    [
        "b2HexColor",
    ];

    // ===== Def 構造体 (HasMetamethods = true) =====

    private static readonly HashSet<string> DefStructs =
    [
        "b2WorldDef", "b2BodyDef", "b2ShapeDef", "b2ChainDef",
        "b2DistanceJointDef", "b2MotorJointDef", "b2MouseJointDef",
        "b2FilterJointDef", "b2PrismaticJointDef", "b2RevoluteJointDef",
        "b2WeldJointDef", "b2WheelJointDef",
        "b2Filter", "b2QueryFilter", "b2SurfaceMaterial",
        "b2ExplosionDef",
    ];

    // ===== Handle 構造体 (value-type userdata, HasMetamethods = false) =====

    private static readonly HashSet<string> HandleStructs =
    [
        "b2WorldId", "b2BodyId", "b2ShapeId", "b2JointId", "b2ChainId",
    ];

    // ===== Geometry 構造体 (HasMetamethods = true for field access) =====

    private static readonly HashSet<string> GeometryStructs =
    [
        "b2Circle", "b2Capsule", "b2Segment", "b2Polygon",
        "b2ChainSegment", "b2Hull",
        "b2MassData",
        "b2RayCastInput", "b2ShapeProxy", "b2ShapeCastInput", "b2CastOutput",
        "b2RayResult",
    ];

    // ===== Struct フィールド スキップ =====

    private static readonly HashSet<string> SkipFields =
    [
        // void* userData はスキップ
        "userData",
        // void* userTaskContext はスキップ
        "userTaskContext",
        // Callback function pointers
        "enqueueTask", "finishTask",
        "frictionCallback", "restitutionCallback",
    ];

    // ===== Allowed Enums =====

    private static readonly HashSet<string> AllowedEnums =
    [
        "b2BodyType", "b2ShapeType", "b2JointType",
    ];

    // ===== BuildSpec =====

    public ModuleSpec BuildSpec(TypeRegistry reg, Dictionary<string, string> prefixToModule, SourceLink? sourceLink = null)
    {
        var enumNames = reg.AllDecls.OfType<Enums>().Select(e => e.Name).ToHashSet();
        var allStructs = reg.AllDecls.OfType<Structs>()
            .GroupBy(s => s.Name).ToDictionary(g => g.Key, g => g.First());

        // 型解決
        BindingType Resolve(Types t) => t switch
        {
            Types.Int => new BindingType.Int(),
            Types.Int64 => new BindingType.Int64(),
            Types.UInt32 => new BindingType.UInt32(),
            Types.UInt64 => new BindingType.UInt64(),
            Types.Size => new BindingType.Size(),
            Types.Float => new BindingType.Float(),
            Types.Double => new BindingType.Double(),
            Types.Bool => new BindingType.Bool(),
            Types.String => new BindingType.Str(),
            Types.Ptr(Types.Void) => new BindingType.VoidPtr(),
            Types.ConstPtr(Types.String) => new BindingType.Str(),
            Types.ConstPtr(var inner) => new BindingType.ConstPtr(Resolve(inner)),
            Types.Ptr(var inner) => new BindingType.Ptr(Resolve(inner)),
            // Box2D math types → Custom
            Types.StructRef("b2Vec2") => B2Vec2Type,
            Types.StructRef("b2Rot") => B2RotType,
            Types.StructRef("b2Transform") => B2TransformType,
            Types.StructRef("b2AABB") => B2AABBType,
            // Box2D typedef aliases
            Types.StructRef("uint8_t") => new BindingType.UInt32(),
            Types.StructRef("uint16_t") => new BindingType.UInt32(),
            Types.StructRef("uint32_t") => new BindingType.UInt32(),
            Types.StructRef("uint64_t") => new BindingType.UInt64(),
            Types.StructRef("int32_t") => new BindingType.Int(),
            Types.StructRef("int16_t") => new BindingType.Int(),
            // Enums
            Types.StructRef(var name) when enumNames.Contains(name) && AllowedEnums.Contains(name) =>
                new BindingType.Enum(name, $"{ModuleName}.{Pipeline.ToPascalCase(Pipeline.StripPrefix(name, Prefix))}"),
            Types.StructRef(var name) when enumNames.Contains(name) =>
                new BindingType.Int(),  // non-allowed enums → int
            // Handle types
            Types.StructRef(var name) when HandleStructs.Contains(name) =>
                HandleType(name),
            // Known structs
            Types.StructRef(var name) when allStructs.ContainsKey(name) && !SkipStructs.Contains(name) =>
                new BindingType.Struct(name,
                    $"{ModuleName}.{Pipeline.ToPascalCase(Pipeline.StripPrefix(name, Prefix))}",
                    $"{ModuleName}.{Pipeline.ToPascalCase(Pipeline.StripPrefix(name, Prefix))}"),
            Types.StructRef("b2CosSin") => B2CosSinType,
            // Fixed arrays
            Types.Array(var inner, var len) => new BindingType.FixedArray(Resolve(inner), len),
            Types.Void => new BindingType.Void(),
            _ => new BindingType.Void(),
        };

        // ===== Structs =====
        var structs = new List<StructBinding>();

        var processedStructs = new HashSet<string>();
        foreach (var s in reg.OwnStructs)
        {
            if (SkipStructs.Contains(s.Name)) continue;
            if (!processedStructs.Add(s.Name)) continue;
            if (!DefStructs.Contains(s.Name) && !HandleStructs.Contains(s.Name) && !GeometryStructs.Contains(s.Name))
                continue;

            var hasMeta = DefStructs.Contains(s.Name) || GeometryStructs.Contains(s.Name);
            var fields = new List<FieldBinding>();

            foreach (var f in s.Fields)
            {
                if (SkipFields.Contains(f.Name)) continue;
                // const b2Vec2* points / const b2SurfaceMaterial* materials → skip (handled by ExtraCCode)
                if (f.Name == "points" || f.Name == "materials") continue;
                // count / materialCount → skip (derived from array length)
                if (s.Name == "b2ChainDef" && (f.Name == "count" || f.Name == "materialCount")) continue;

                var fieldType = Resolve(f.ParsedType);
                // Callback / function pointer fields → skip
                if (fieldType is BindingType.Void && f.ParsedType is Types.Ptr(Types.StructRef(_)))
                    continue;

                fields.Add(new FieldBinding(f.Name, MapFieldName(f.Name), fieldType));
            }

            var pascalName = Pipeline.ToPascalCase(Pipeline.StripPrefix(s.Name, Prefix));
            var isHandle = HandleStructs.Contains(s.Name);
            structs.Add(new StructBinding(
                s.Name, pascalName,
                $"{ModuleName}.{pascalName}",
                hasMeta, fields,
                GetLink(s, sourceLink),
                IsHandleType: isHandle));
        }

        // ===== Functions =====
        var funcs = new List<FuncBinding>();

        foreach (var f in reg.OwnFuncs)
        {
            if (SkipFuncs.Contains(f.Name)) continue;
            if (SkipFuncPrefixes.Any(p => f.Name.StartsWith(p))) continue;
            // Skip inline math functions
            if (f.Name.StartsWith("b2") && !f.Name.Contains("_") && !IsTopLevelFunc(f.Name)) continue;

            var retType = Resolve(CTypeParser.ParseReturnType(f.TypeStr));
            var parms = new List<ParamBinding>();
            var skip = false;

            foreach (var p in f.Params)
            {
                var pt = Resolve(p.ParsedType);
                // Skip functions with unsupported parameter types
                if (pt is BindingType.Void && p.ParsedType is not Types.Void)
                {
                    skip = true;
                    break;
                }
                // Skip functions with ConstPtr/Ptr to Void (unresolved struct)
                if (pt is BindingType.ConstPtr(BindingType.Void) or BindingType.Ptr(BindingType.Void))
                {
                    skip = true;
                    break;
                }
                // ConstPtr to struct → pass as const ptr
                parms.Add(new ParamBinding(p.Name, pt));
            }

            if (skip) continue;

            var luaName = ToLuaFuncName(f.Name);
            funcs.Add(new FuncBinding(f.Name, luaName, parms, retType, GetLink(f, sourceLink)));
        }

        // ===== Enums =====
        var enums = new List<EnumBinding>();

        foreach (var e in reg.OwnEnums)
        {
            if (!AllowedEnums.Contains(e.Name)) continue;
            if (SkipEnums.Contains(e.Name)) continue;

            var luaName = $"{ModuleName}.{Pipeline.ToPascalCase(Pipeline.StripPrefix(e.Name, Prefix))}";
            var fieldName = Pipeline.ToPascalCase(Pipeline.StripPrefix(e.Name, Prefix));
            var next = 0;
            var items = e.Items
                .Where(i => !i.Name.EndsWith("Count") && !i.Name.StartsWith("_"))
                .Select(i =>
                {
                    int? val = i.Value != null && int.TryParse(i.Value, out var v) ? v : null;
                    var resolvedVal = val ?? next;
                    next = resolvedVal + 1;
                    var itemName = B2EnumItemName(i.Name, e.Name);
                    return new EnumItemBinding(itemName, i.Name, resolvedVal);
                }).ToList();
            enums.Add(new EnumBinding(e.Name, luaName, fieldName, items, GetLink(e, sourceLink)));
        }

        // ===== ExtraLuaRegs + ExtraLuaFuncs =====
        var extraRegs = new List<(string LuaName, string CFunc)>
        {
            ("DefaultWorldDef", "l_b2d_default_world_def"),
            ("WorldGetContactEvents", "l_b2d_world_get_contact_events"),
            ("WorldGetSensorEvents", "l_b2d_world_get_sensor_events"),
            ("WorldGetBodyEvents", "l_b2d_world_get_body_events"),
            ("BodyGetShapes", "l_b2d_body_get_shapes"),
            ("BodyGetJoints", "l_b2d_body_get_joints"),
            ("WorldCastRayClosest", "l_b2d_world_cast_ray_closest"),
            ("WorldOverlapAabb", "l_b2d_world_overlap_aabb"),
            ("WorldCastRay", "l_b2d_world_cast_ray"),
        };

        var extraLuaFuncs = new List<FuncBinding>
        {
            new("l_b2d_default_world_def", "DefaultWorldDef", [],
                HandleType("b2WorldDef"), null),
            new("l_b2d_world_get_contact_events", "WorldGetContactEvents",
                [new ParamBinding("worldId", HandleType("b2WorldId"))],
                new BindingType.Void(), null),
            new("l_b2d_world_get_sensor_events", "WorldGetSensorEvents",
                [new ParamBinding("worldId", HandleType("b2WorldId"))],
                new BindingType.Void(), null),
            new("l_b2d_world_get_body_events", "WorldGetBodyEvents",
                [new ParamBinding("worldId", HandleType("b2WorldId"))],
                new BindingType.Void(), null),
            new("l_b2d_body_get_shapes", "BodyGetShapes",
                [new ParamBinding("bodyId", HandleType("b2BodyId"))],
                new BindingType.Void(), null),
            new("l_b2d_body_get_joints", "BodyGetJoints",
                [new ParamBinding("bodyId", HandleType("b2BodyId"))],
                new BindingType.Void(), null),
            new("l_b2d_world_cast_ray_closest", "WorldCastRayClosest",
                [
                    new ParamBinding("worldId", HandleType("b2WorldId")),
                    new ParamBinding("origin", B2Vec2Type),
                    new ParamBinding("translation", B2Vec2Type),
                    new ParamBinding("filter", new BindingType.Struct("b2QueryFilter", "b2d.QueryFilter", "b2d.QueryFilter")),
                ],
                new BindingType.Void(), null),
            new("l_b2d_world_overlap_aabb", "WorldOverlapAabb",
                [
                    new ParamBinding("worldId", HandleType("b2WorldId")),
                    new ParamBinding("aabb", B2AABBType),
                    new ParamBinding("filter", new BindingType.Struct("b2QueryFilter", "b2d.QueryFilter", "b2d.QueryFilter")),
                    new ParamBinding("callback", new BindingType.Callback([], null)),
                ],
                new BindingType.Void(), null),
            new("l_b2d_world_cast_ray", "WorldCastRay",
                [
                    new ParamBinding("worldId", HandleType("b2WorldId")),
                    new ParamBinding("origin", B2Vec2Type),
                    new ParamBinding("translation", B2Vec2Type),
                    new ParamBinding("filter", new BindingType.Struct("b2QueryFilter", "b2d.QueryFilter", "b2d.QueryFilter")),
                    new ParamBinding("callback", new BindingType.Callback([], null)),
                ],
                new BindingType.Void(), null),
        };

        return new ModuleSpec(
            ModuleName, Prefix,
            ["box2d/box2d.h", "box2d/math_functions.h", "box2d/collision.h"],
            ExtraCCode(),
            structs, funcs, enums,
            extraRegs,
            [],
            ExtraLuaFuncs: extraLuaFuncs);
    }

    // ===== IModule 実装 =====

    public string GenerateC(TypeRegistry reg, Dictionary<string, string> prefixToModule)
    {
        var spec = SpecTransform.ExpandHandleTypes(BuildSpec(reg, prefixToModule));
        return CBinding.CBindingGen.Generate(spec);
    }

    public string GenerateLua(TypeRegistry reg, Dictionary<string, string> prefixToModule, SourceLink? sourceLink = null)
    {
        var spec = SpecTransform.ExpandHandleTypes(BuildSpec(reg, prefixToModule, sourceLink));
        return LuaCats.LuaCatsGen.Generate(spec);
    }

    // ===== 名前変換 =====

    /// <summary>
    /// Box2D 関数名 → Lua 名 (PascalCase)
    /// b2CreateWorld → CreateWorld
    /// b2World_Step → WorldStep
    /// b2Body_GetPosition → BodyGetPosition
    /// b2DefaultBodyDef → DefaultBodyDef
    /// b2MakeBox → MakeBox
    /// </summary>
    private static string ToLuaFuncName(string cName)
    {
        var stripped = Pipeline.StripPrefix(cName, "b2");
        return Pipeline.ToPascalCase(stripped);
    }

    /// <summary>Box2D enum item name → Lua name (strip common prefix)</summary>
    private static string B2EnumItemName(string itemName, string enumName)
    {
        // b2_staticBody → STATIC_BODY, b2_dynamicBody → DYNAMIC_BODY
        var stripped = Pipeline.StripPrefix(itemName, "b2_");
        return Pipeline.ToUpperSnakeCase(stripped);
    }

    private static string MapFieldName(string name) => name;

    /// <summary>Top-level functions (not inline math)</summary>
    private static bool IsTopLevelFunc(string name) =>
        name.StartsWith("b2Create") ||
        name.StartsWith("b2Destroy") ||
        name.StartsWith("b2Default") ||
        name.StartsWith("b2Make") ||
        name.StartsWith("b2Compute") ||
        name.StartsWith("b2Validate") ||
        name.StartsWith("b2Transform") ||
        name.StartsWith("b2PointIn") ||
        name.StartsWith("b2RayCast") ||
        name.StartsWith("b2ShapeCast") ||
        name.StartsWith("b2Collide") ||
        name.StartsWith("b2GetVersion") ||
        name.StartsWith("b2GetTicks") ||
        name.StartsWith("b2GetMilliseconds") ||
        name.StartsWith("b2GetByteCount") ||
        name == "b2Atan2" ||
        name == "b2ComputeCosSin" ||
        name == "b2SetLengthUnitsPerMeter" ||
        name == "b2GetLengthUnitsPerMeter";

    // ===== ExtraCCode =====

    private static string ExtraCCode() => """
        /* Serial task system for single-threaded Box2D */
        static void b2d_enqueue_task(b2TaskCallback* task, int32_t itemCount,
            int32_t minRange, void* taskContext, void* userContext)
        {
            (void)userContext;
            task(0, itemCount, 0, taskContext);
        }

        static void b2d_finish_task(void* userTask, void* userContext)
        {
            (void)userTask;
            (void)userContext;
        }

        /* Default world def with serial task system */
        static int l_b2d_default_world_def(lua_State *L) {
            b2WorldDef* ud = (b2WorldDef*)lua_newuserdatauv(L, sizeof(b2WorldDef), 0);
            *ud = b2DefaultWorldDef();
            ud->enqueueTask = (b2EnqueueTaskCallback*)b2d_enqueue_task;
            ud->finishTask = b2d_finish_task;
            luaL_setmetatable(L, "b2d.WorldDef");
            return 1;
        }

        /* Contact events → {begin={...}, end_={...}, hit={...}} */
        static int l_b2d_world_get_contact_events(lua_State *L) {
            b2WorldId worldId = *(b2WorldId*)luaL_checkudata(L, 1, "b2d.WorldId");
            b2ContactEvents events = b2World_GetContactEvents(worldId);

            lua_newtable(L);

            /* begin */
            lua_newtable(L);
            for (int i = 0; i < events.beginCount; i++) {
                lua_newtable(L);
                b2ShapeId* sidA = (b2ShapeId*)lua_newuserdatauv(L, sizeof(b2ShapeId), 0);
                *sidA = events.beginEvents[i].shapeIdA;
                luaL_setmetatable(L, "b2d.ShapeId");
                lua_setfield(L, -2, "shapeIdA");
                b2ShapeId* sidB = (b2ShapeId*)lua_newuserdatauv(L, sizeof(b2ShapeId), 0);
                *sidB = events.beginEvents[i].shapeIdB;
                luaL_setmetatable(L, "b2d.ShapeId");
                lua_setfield(L, -2, "shapeIdB");
                lua_rawseti(L, -2, i + 1);
            }
            lua_setfield(L, -2, "begin");

            /* end_ (avoid Lua keyword) */
            lua_newtable(L);
            for (int i = 0; i < events.endCount; i++) {
                lua_newtable(L);
                b2ShapeId* sidA = (b2ShapeId*)lua_newuserdatauv(L, sizeof(b2ShapeId), 0);
                *sidA = events.endEvents[i].shapeIdA;
                luaL_setmetatable(L, "b2d.ShapeId");
                lua_setfield(L, -2, "shapeIdA");
                b2ShapeId* sidB = (b2ShapeId*)lua_newuserdatauv(L, sizeof(b2ShapeId), 0);
                *sidB = events.endEvents[i].shapeIdB;
                luaL_setmetatable(L, "b2d.ShapeId");
                lua_setfield(L, -2, "shapeIdB");
                lua_rawseti(L, -2, i + 1);
            }
            lua_setfield(L, -2, "end_");

            /* hit */
            lua_newtable(L);
            for (int i = 0; i < events.hitCount; i++) {
                lua_newtable(L);
                b2ShapeId* sidA = (b2ShapeId*)lua_newuserdatauv(L, sizeof(b2ShapeId), 0);
                *sidA = events.hitEvents[i].shapeIdA;
                luaL_setmetatable(L, "b2d.ShapeId");
                lua_setfield(L, -2, "shapeIdA");
                b2ShapeId* sidB = (b2ShapeId*)lua_newuserdatauv(L, sizeof(b2ShapeId), 0);
                *sidB = events.hitEvents[i].shapeIdB;
                luaL_setmetatable(L, "b2d.ShapeId");
                lua_setfield(L, -2, "shapeIdB");
                lua_newtable(L);
                lua_pushnumber(L, events.hitEvents[i].point.x); lua_rawseti(L, -2, 1);
                lua_pushnumber(L, events.hitEvents[i].point.y); lua_rawseti(L, -2, 2);
                lua_setfield(L, -2, "point");
                lua_newtable(L);
                lua_pushnumber(L, events.hitEvents[i].normal.x); lua_rawseti(L, -2, 1);
                lua_pushnumber(L, events.hitEvents[i].normal.y); lua_rawseti(L, -2, 2);
                lua_setfield(L, -2, "normal");
                lua_pushnumber(L, events.hitEvents[i].approachSpeed);
                lua_setfield(L, -2, "approachSpeed");
                lua_rawseti(L, -2, i + 1);
            }
            lua_setfield(L, -2, "hit");

            return 1;
        }

        /* Sensor events → {begin={...}, end_={...}} */
        static int l_b2d_world_get_sensor_events(lua_State *L) {
            b2WorldId worldId = *(b2WorldId*)luaL_checkudata(L, 1, "b2d.WorldId");
            b2SensorEvents events = b2World_GetSensorEvents(worldId);

            lua_newtable(L);

            lua_newtable(L);
            for (int i = 0; i < events.beginCount; i++) {
                lua_newtable(L);
                b2ShapeId* sid = (b2ShapeId*)lua_newuserdatauv(L, sizeof(b2ShapeId), 0);
                *sid = events.beginEvents[i].sensorShapeId;
                luaL_setmetatable(L, "b2d.ShapeId");
                lua_setfield(L, -2, "sensorShapeId");
                sid = (b2ShapeId*)lua_newuserdatauv(L, sizeof(b2ShapeId), 0);
                *sid = events.beginEvents[i].visitorShapeId;
                luaL_setmetatable(L, "b2d.ShapeId");
                lua_setfield(L, -2, "visitorShapeId");
                lua_rawseti(L, -2, i + 1);
            }
            lua_setfield(L, -2, "begin");

            lua_newtable(L);
            for (int i = 0; i < events.endCount; i++) {
                lua_newtable(L);
                b2ShapeId* sid = (b2ShapeId*)lua_newuserdatauv(L, sizeof(b2ShapeId), 0);
                *sid = events.endEvents[i].sensorShapeId;
                luaL_setmetatable(L, "b2d.ShapeId");
                lua_setfield(L, -2, "sensorShapeId");
                sid = (b2ShapeId*)lua_newuserdatauv(L, sizeof(b2ShapeId), 0);
                *sid = events.endEvents[i].visitorShapeId;
                luaL_setmetatable(L, "b2d.ShapeId");
                lua_setfield(L, -2, "visitorShapeId");
                lua_rawseti(L, -2, i + 1);
            }
            lua_setfield(L, -2, "end_");

            return 1;
        }

        /* Body events → {move={...}} */
        static int l_b2d_world_get_body_events(lua_State *L) {
            b2WorldId worldId = *(b2WorldId*)luaL_checkudata(L, 1, "b2d.WorldId");
            b2BodyEvents events = b2World_GetBodyEvents(worldId);

            lua_newtable(L);
            lua_newtable(L);
            for (int i = 0; i < events.moveCount; i++) {
                lua_newtable(L);
                /* transform as {{px,py},{c,s}} */
                lua_newtable(L);
                lua_newtable(L);
                lua_pushnumber(L, events.moveEvents[i].transform.p.x); lua_rawseti(L, -2, 1);
                lua_pushnumber(L, events.moveEvents[i].transform.p.y); lua_rawseti(L, -2, 2);
                lua_rawseti(L, -2, 1);
                lua_newtable(L);
                lua_pushnumber(L, events.moveEvents[i].transform.q.c); lua_rawseti(L, -2, 1);
                lua_pushnumber(L, events.moveEvents[i].transform.q.s); lua_rawseti(L, -2, 2);
                lua_rawseti(L, -2, 2);
                lua_setfield(L, -2, "transform");
                b2BodyId* bid = (b2BodyId*)lua_newuserdatauv(L, sizeof(b2BodyId), 0);
                *bid = events.moveEvents[i].bodyId;
                luaL_setmetatable(L, "b2d.BodyId");
                lua_setfield(L, -2, "bodyId");
                lua_pushboolean(L, events.moveEvents[i].fellAsleep);
                lua_setfield(L, -2, "fellAsleep");
                lua_rawseti(L, -2, i + 1);
            }
            lua_setfield(L, -2, "move");

            return 1;
        }

        /* Body get shapes → table of ShapeId */
        static int l_b2d_body_get_shapes(lua_State *L) {
            b2BodyId bodyId = *(b2BodyId*)luaL_checkudata(L, 1, "b2d.BodyId");
            int count = b2Body_GetShapeCount(bodyId);
            b2ShapeId* shapes = (b2ShapeId*)malloc(count * sizeof(b2ShapeId));
            b2Body_GetShapes(bodyId, shapes, count);
            lua_newtable(L);
            for (int i = 0; i < count; i++) {
                b2ShapeId* ud = (b2ShapeId*)lua_newuserdatauv(L, sizeof(b2ShapeId), 0);
                *ud = shapes[i];
                luaL_setmetatable(L, "b2d.ShapeId");
                lua_rawseti(L, -2, i + 1);
            }
            free(shapes);
            return 1;
        }

        /* Body get joints → table of JointId */
        static int l_b2d_body_get_joints(lua_State *L) {
            b2BodyId bodyId = *(b2BodyId*)luaL_checkudata(L, 1, "b2d.BodyId");
            int count = b2Body_GetJointCount(bodyId);
            b2JointId* joints = (b2JointId*)malloc(count * sizeof(b2JointId));
            b2Body_GetJoints(bodyId, joints, count);
            lua_newtable(L);
            for (int i = 0; i < count; i++) {
                b2JointId* ud = (b2JointId*)lua_newuserdatauv(L, sizeof(b2JointId), 0);
                *ud = joints[i];
                luaL_setmetatable(L, "b2d.JointId");
                lua_rawseti(L, -2, i + 1);
            }
            free(joints);
            return 1;
        }

        /* CastRayClosest wrapper */
        static int l_b2d_world_cast_ray_closest(lua_State *L) {
            b2WorldId worldId = *(b2WorldId*)luaL_checkudata(L, 1, "b2d.WorldId");
            luaL_checktype(L, 2, LUA_TTABLE);
            b2Vec2 origin;
            lua_rawgeti(L, 2, 1); origin.x = (float)lua_tonumber(L, -1); lua_pop(L, 1);
            lua_rawgeti(L, 2, 2); origin.y = (float)lua_tonumber(L, -1); lua_pop(L, 1);
            luaL_checktype(L, 3, LUA_TTABLE);
            b2Vec2 translation;
            lua_rawgeti(L, 3, 1); translation.x = (float)lua_tonumber(L, -1); lua_pop(L, 1);
            lua_rawgeti(L, 3, 2); translation.y = (float)lua_tonumber(L, -1); lua_pop(L, 1);
            b2QueryFilter filter = *(b2QueryFilter*)luaL_checkudata(L, 4, "b2d.QueryFilter");
            b2RayResult result = b2World_CastRayClosest(worldId, origin, translation, filter);
            /* Return table: {shapeId, point, normal, fraction, hit} */
            lua_newtable(L);
            b2ShapeId* sid = (b2ShapeId*)lua_newuserdatauv(L, sizeof(b2ShapeId), 0);
            *sid = result.shapeId;
            luaL_setmetatable(L, "b2d.ShapeId");
            lua_setfield(L, -2, "shapeId");
            lua_newtable(L);
            lua_pushnumber(L, result.point.x); lua_rawseti(L, -2, 1);
            lua_pushnumber(L, result.point.y); lua_rawseti(L, -2, 2);
            lua_setfield(L, -2, "point");
            lua_newtable(L);
            lua_pushnumber(L, result.normal.x); lua_rawseti(L, -2, 1);
            lua_pushnumber(L, result.normal.y); lua_rawseti(L, -2, 2);
            lua_setfield(L, -2, "normal");
            lua_pushnumber(L, result.fraction);
            lua_setfield(L, -2, "fraction");
            lua_pushboolean(L, result.hit);
            lua_setfield(L, -2, "hit");
            return 1;
        }

        /* Overlap AABB with Lua callback */
        typedef struct {
            lua_State* L;
            int callback_idx;
        } b2d_query_context;

        static bool b2d_overlap_callback(b2ShapeId shapeId, void* context) {
            b2d_query_context* ctx = (b2d_query_context*)context;
            lua_pushvalue(ctx->L, ctx->callback_idx);
            b2ShapeId* ud = (b2ShapeId*)lua_newuserdatauv(ctx->L, sizeof(b2ShapeId), 0);
            *ud = shapeId;
            luaL_setmetatable(ctx->L, "b2d.ShapeId");
            lua_call(ctx->L, 1, 1);
            bool cont = lua_toboolean(ctx->L, -1);
            lua_pop(ctx->L, 1);
            return cont;
        }

        static int l_b2d_world_overlap_aabb(lua_State *L) {
            b2WorldId worldId = *(b2WorldId*)luaL_checkudata(L, 1, "b2d.WorldId");
            luaL_checktype(L, 2, LUA_TTABLE);
            b2AABB aabb;
            lua_rawgeti(L, 2, 1); luaL_checktype(L, -1, LUA_TTABLE);
            lua_rawgeti(L, -1, 1); aabb.lowerBound.x = (float)lua_tonumber(L, -1); lua_pop(L, 1);
            lua_rawgeti(L, -1, 2); aabb.lowerBound.y = (float)lua_tonumber(L, -1); lua_pop(L, 1);
            lua_pop(L, 1);
            lua_rawgeti(L, 2, 2); luaL_checktype(L, -1, LUA_TTABLE);
            lua_rawgeti(L, -1, 1); aabb.upperBound.x = (float)lua_tonumber(L, -1); lua_pop(L, 1);
            lua_rawgeti(L, -1, 2); aabb.upperBound.y = (float)lua_tonumber(L, -1); lua_pop(L, 1);
            lua_pop(L, 1);
            b2QueryFilter filter = *(b2QueryFilter*)luaL_checkudata(L, 3, "b2d.QueryFilter");
            luaL_checktype(L, 4, LUA_TFUNCTION);
            b2d_query_context ctx = { L, 4 };
            b2World_OverlapAABB(worldId, aabb, filter, b2d_overlap_callback, &ctx);
            return 0;
        }

        /* CastRay with Lua callback */
        static float b2d_cast_callback(b2ShapeId shapeId, b2Vec2 point, b2Vec2 normal, float fraction, void* context) {
            b2d_query_context* ctx = (b2d_query_context*)context;
            lua_pushvalue(ctx->L, ctx->callback_idx);
            b2ShapeId* ud = (b2ShapeId*)lua_newuserdatauv(ctx->L, sizeof(b2ShapeId), 0);
            *ud = shapeId;
            luaL_setmetatable(ctx->L, "b2d.ShapeId");
            lua_newtable(ctx->L);
            lua_pushnumber(ctx->L, point.x); lua_rawseti(ctx->L, -2, 1);
            lua_pushnumber(ctx->L, point.y); lua_rawseti(ctx->L, -2, 2);
            lua_newtable(ctx->L);
            lua_pushnumber(ctx->L, normal.x); lua_rawseti(ctx->L, -2, 1);
            lua_pushnumber(ctx->L, normal.y); lua_rawseti(ctx->L, -2, 2);
            lua_pushnumber(ctx->L, fraction);
            lua_call(ctx->L, 4, 1);
            float result = (float)lua_tonumber(ctx->L, -1);
            lua_pop(ctx->L, 1);
            return result;
        }

        static int l_b2d_world_cast_ray(lua_State *L) {
            b2WorldId worldId = *(b2WorldId*)luaL_checkudata(L, 1, "b2d.WorldId");
            luaL_checktype(L, 2, LUA_TTABLE);
            b2Vec2 origin;
            lua_rawgeti(L, 2, 1); origin.x = (float)lua_tonumber(L, -1); lua_pop(L, 1);
            lua_rawgeti(L, 2, 2); origin.y = (float)lua_tonumber(L, -1); lua_pop(L, 1);
            luaL_checktype(L, 3, LUA_TTABLE);
            b2Vec2 translation;
            lua_rawgeti(L, 3, 1); translation.x = (float)lua_tonumber(L, -1); lua_pop(L, 1);
            lua_rawgeti(L, 3, 2); translation.y = (float)lua_tonumber(L, -1); lua_pop(L, 1);
            b2QueryFilter filter = *(b2QueryFilter*)luaL_checkudata(L, 4, "b2d.QueryFilter");
            luaL_checktype(L, 5, LUA_TFUNCTION);
            b2d_query_context ctx = { L, 5 };
            b2World_CastRay(worldId, origin, translation, filter, b2d_cast_callback, &ctx);
            return 0;
        }

        """;

    // ===== ヘルパー =====

    private static string? GetLink(Decl d, SourceLink? sourceLink)
    {
        if (sourceLink == null) return null;
        var line = d switch
        {
            Funcs f => f.Line,
            Enums e => e.Line,
            Structs s => s.Line,
            _ => null
        };
        return line is int l ? sourceLink.GetLink(l) : null;
    }
}
