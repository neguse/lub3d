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

    // ===== ValueStruct 型定義 (b2Vec2, b2Rot, etc.) =====

    /// <summary>b2Vec2 → Lua table {x, y}</summary>
    private static readonly BindingType B2Vec2Type = new BindingType.ValueStruct(
        "b2Vec2", "number[]",
        [new BindingType.ScalarField("x"), new BindingType.ScalarField("y")]);

    /// <summary>b2CosSin → Lua table {cosine, sine}</summary>
    private static readonly BindingType B2CosSinType = new BindingType.ValueStruct(
        "b2CosSin", "number[]",
        [new BindingType.ScalarField("cosine"), new BindingType.ScalarField("sine")],
        Settable: false);

    /// <summary>b2Rot → Lua table {c, s}</summary>
    private static readonly BindingType B2RotType = new BindingType.ValueStruct(
        "b2Rot", "number[]",
        [new BindingType.ScalarField("c"), new BindingType.ScalarField("s")]);

    /// <summary>b2Transform → Lua table {{px,py},{c,s}}</summary>
    private static readonly BindingType B2TransformType = new BindingType.ValueStruct(
        "b2Transform", "number[][]",
        [new BindingType.NestedFields("p", ["x", "y"]),
         new BindingType.NestedFields("q", ["c", "s"])],
        Settable: false);

    /// <summary>b2AABB → Lua table {{lx,ly},{ux,uy}}</summary>
    private static readonly BindingType B2AABBType = new BindingType.ValueStruct(
        "b2AABB", "number[][]",
        [new BindingType.NestedFields("lowerBound", ["x", "y"]),
         new BindingType.NestedFields("upperBound", ["x", "y"])],
        Settable: false);

    // ===== Callback 型定義 =====

    /// <summary>b2OverlapResultFcn: bool callback(b2ShapeId shapeId, void* context)</summary>
    private BindingType OverlapCallbackType => new BindingType.Callback(
        [("shapeId", HandleType("b2ShapeId"))], new BindingType.Bool());

    /// <summary>b2CastResultFcn: float callback(b2ShapeId shapeId, b2Vec2 point, b2Vec2 normal, float fraction, void* context)</summary>
    private BindingType CastCallbackType => new BindingType.Callback(
        [("shapeId", HandleType("b2ShapeId")), ("point", B2Vec2Type),
         ("normal", B2Vec2Type), ("fraction", new BindingType.Float())],
        new BindingType.Float());

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
        // Query functions (need Lua callback wrappers → ExtraCCode or CallbackBridge)
        "b2World_OverlapShape",
        "b2World_CastShape",
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
            // Box2D callback typedefs (must precede generic Ptr/ConstPtr)
            Types.Ptr(Types.StructRef("b2OverlapResultFcn")) => OverlapCallbackType,
            Types.Ptr(Types.StructRef("b2CastResultFcn")) => CastCallbackType,
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
            var skipNextVoidPtr = false;

            foreach (var p in f.Params)
            {
                // Skip void* context param that follows a callback
                if (skipNextVoidPtr && p.ParsedType is Types.Ptr(Types.Void))
                {
                    skipNextVoidPtr = false;
                    continue;
                }
                skipNextVoidPtr = false;

                var pt = Resolve(p.ParsedType);

                // Callback parameter → set CallbackBridge and skip next void* context
                if (pt is BindingType.Callback)
                {
                    parms.Add(new ParamBinding(p.Name, pt, CallbackBridge: CallbackBridgeMode.Immediate));
                    skipNextVoidPtr = true;
                    continue;
                }

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
            ("default_world_def", "l_b2d_default_world_def"),
            ("world_get_contact_events", "l_b2d_world_get_contact_events"),
            ("world_get_sensor_events", "l_b2d_world_get_sensor_events"),
            ("world_get_body_events", "l_b2d_world_get_body_events"),
            ("body_get_shapes", "l_b2d_body_get_shapes"),
            ("body_get_joints", "l_b2d_body_get_joints"),
            ("world_cast_ray_closest", "l_b2d_world_cast_ray_closest"),
        };

        var extraLuaFuncs = new List<FuncBinding>
        {
            new("l_b2d_default_world_def", "default_world_def", [],
                HandleType("b2WorldDef"), null),
            new("l_b2d_world_get_contact_events", "world_get_contact_events",
                [new ParamBinding("worldId", HandleType("b2WorldId"))],
                new BindingType.Void(), null),
            new("l_b2d_world_get_sensor_events", "world_get_sensor_events",
                [new ParamBinding("worldId", HandleType("b2WorldId"))],
                new BindingType.Void(), null),
            new("l_b2d_world_get_body_events", "world_get_body_events",
                [new ParamBinding("worldId", HandleType("b2WorldId"))],
                new BindingType.Void(), null),
            new("l_b2d_body_get_shapes", "body_get_shapes",
                [new ParamBinding("bodyId", HandleType("b2BodyId"))],
                new BindingType.Void(), null),
            new("l_b2d_body_get_joints", "body_get_joints",
                [new ParamBinding("bodyId", HandleType("b2BodyId"))],
                new BindingType.Void(), null),
            new("l_b2d_world_cast_ray_closest", "world_cast_ray_closest",
                [
                    new ParamBinding("worldId", HandleType("b2WorldId")),
                    new ParamBinding("origin", B2Vec2Type),
                    new ParamBinding("translation", B2Vec2Type),
                    new ParamBinding("filter", new BindingType.Struct("b2QueryFilter", "b2d.QueryFilter", "b2d.QueryFilter")),
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
    /// Box2D 関数名 → Lua 名 (snake_case)
    /// b2CreateWorld → create_world
    /// b2World_Step → world_step
    /// b2Body_GetPosition → body_get_position
    /// b2DefaultBodyDef → default_body_def
    /// b2MakeBox → make_box
    /// </summary>
    private static string ToLuaFuncName(string cName)
    {
        var stripped = Pipeline.StripPrefix(cName, "b2");
        return Pipeline.ToSnakeCase(stripped);
    }

    /// <summary>Box2D enum item name → Lua name (strip common prefix)</summary>
    private static string B2EnumItemName(string itemName, string enumName)
    {
        // b2_staticBody → STATIC_BODY, b2_dynamicBody → DYNAMIC_BODY
        var stripped = Pipeline.StripPrefix(itemName, "b2_");
        return Pipeline.ToUpperSnakeCase(stripped);
    }

    private static string MapFieldName(string name) => Pipeline.ToSnakeCase(name);

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

        /* Contact events → {begin_events={...}, end_events={...}, hit_events={...}} */
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
                lua_setfield(L, -2, "shape_id_a");
                b2ShapeId* sidB = (b2ShapeId*)lua_newuserdatauv(L, sizeof(b2ShapeId), 0);
                *sidB = events.beginEvents[i].shapeIdB;
                luaL_setmetatable(L, "b2d.ShapeId");
                lua_setfield(L, -2, "shape_id_b");
                lua_rawseti(L, -2, i + 1);
            }
            lua_setfield(L, -2, "begin_events");

            /* endEvents */
            lua_newtable(L);
            for (int i = 0; i < events.endCount; i++) {
                lua_newtable(L);
                b2ShapeId* sidA = (b2ShapeId*)lua_newuserdatauv(L, sizeof(b2ShapeId), 0);
                *sidA = events.endEvents[i].shapeIdA;
                luaL_setmetatable(L, "b2d.ShapeId");
                lua_setfield(L, -2, "shape_id_a");
                b2ShapeId* sidB = (b2ShapeId*)lua_newuserdatauv(L, sizeof(b2ShapeId), 0);
                *sidB = events.endEvents[i].shapeIdB;
                luaL_setmetatable(L, "b2d.ShapeId");
                lua_setfield(L, -2, "shape_id_b");
                lua_rawseti(L, -2, i + 1);
            }
            lua_setfield(L, -2, "end_events");

            /* hitEvents */
            lua_newtable(L);
            for (int i = 0; i < events.hitCount; i++) {
                lua_newtable(L);
                b2ShapeId* sidA = (b2ShapeId*)lua_newuserdatauv(L, sizeof(b2ShapeId), 0);
                *sidA = events.hitEvents[i].shapeIdA;
                luaL_setmetatable(L, "b2d.ShapeId");
                lua_setfield(L, -2, "shape_id_a");
                b2ShapeId* sidB = (b2ShapeId*)lua_newuserdatauv(L, sizeof(b2ShapeId), 0);
                *sidB = events.hitEvents[i].shapeIdB;
                luaL_setmetatable(L, "b2d.ShapeId");
                lua_setfield(L, -2, "shape_id_b");
                lua_newtable(L);
                lua_pushnumber(L, events.hitEvents[i].point.x); lua_rawseti(L, -2, 1);
                lua_pushnumber(L, events.hitEvents[i].point.y); lua_rawseti(L, -2, 2);
                lua_setfield(L, -2, "point");
                lua_newtable(L);
                lua_pushnumber(L, events.hitEvents[i].normal.x); lua_rawseti(L, -2, 1);
                lua_pushnumber(L, events.hitEvents[i].normal.y); lua_rawseti(L, -2, 2);
                lua_setfield(L, -2, "normal");
                lua_pushnumber(L, events.hitEvents[i].approachSpeed);
                lua_setfield(L, -2, "approach_speed");
                lua_rawseti(L, -2, i + 1);
            }
            lua_setfield(L, -2, "hit_events");

            return 1;
        }

        /* Sensor events → {begin_events={...}, end_events={...}} */
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
                lua_setfield(L, -2, "sensor_shape_id");
                sid = (b2ShapeId*)lua_newuserdatauv(L, sizeof(b2ShapeId), 0);
                *sid = events.beginEvents[i].visitorShapeId;
                luaL_setmetatable(L, "b2d.ShapeId");
                lua_setfield(L, -2, "visitor_shape_id");
                lua_rawseti(L, -2, i + 1);
            }
            lua_setfield(L, -2, "begin_events");

            lua_newtable(L);
            for (int i = 0; i < events.endCount; i++) {
                lua_newtable(L);
                b2ShapeId* sid = (b2ShapeId*)lua_newuserdatauv(L, sizeof(b2ShapeId), 0);
                *sid = events.endEvents[i].sensorShapeId;
                luaL_setmetatable(L, "b2d.ShapeId");
                lua_setfield(L, -2, "sensor_shape_id");
                sid = (b2ShapeId*)lua_newuserdatauv(L, sizeof(b2ShapeId), 0);
                *sid = events.endEvents[i].visitorShapeId;
                luaL_setmetatable(L, "b2d.ShapeId");
                lua_setfield(L, -2, "visitor_shape_id");
                lua_rawseti(L, -2, i + 1);
            }
            lua_setfield(L, -2, "end_events");

            return 1;
        }

        /* Body events → {move_events={...}} */
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
                lua_setfield(L, -2, "body_id");
                lua_pushboolean(L, events.moveEvents[i].fellAsleep);
                lua_setfield(L, -2, "fell_asleep");
                lua_rawseti(L, -2, i + 1);
            }
            lua_setfield(L, -2, "move_events");

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
            lua_setfield(L, -2, "shape_id");
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
