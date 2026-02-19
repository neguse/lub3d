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

    /// <summary>const b2Vec2* → Lua table of {x, y} tables</summary>
    private static readonly BindingType B2Vec2ArrayType = new BindingType.ValueStructArray(
        "b2Vec2", "number[][]",
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

    /// <summary>b2Plane → Lua table {{nx,ny}, offset}</summary>
    private static readonly BindingType B2PlaneType = new BindingType.ValueStruct(
        "b2Plane", "number[]",
        [new BindingType.NestedFields("normal", ["x", "y"]),
         new BindingType.ScalarField("offset")]);

    // ===== Callback 型定義 =====

    /// <summary>b2OverlapResultFcn: bool callback(b2ShapeId shapeId, void* context)</summary>
    private BindingType OverlapCallbackType => new BindingType.Callback(
        [("shapeId", HandleType("b2ShapeId"))], new BindingType.Bool());

    /// <summary>b2CastResultFcn: float callback(b2ShapeId shapeId, b2Vec2 point, b2Vec2 normal, float fraction, void* context)</summary>
    private BindingType CastCallbackType => new BindingType.Callback(
        [("shapeId", HandleType("b2ShapeId")), ("point", B2Vec2Type),
         ("normal", B2Vec2Type), ("fraction", new BindingType.Float())],
        new BindingType.Float());

    /// <summary>b2Manifold* → lightuserdata (callback arg としてポインタ渡し)</summary>
    private static readonly BindingType ManifoldPtrType =
        new BindingType.Custom("b2Manifold*", "lightuserdata", null, null, null, null);

    /// <summary>b2PreSolveFcn: bool callback(b2ShapeId shapeIdA, b2ShapeId shapeIdB, b2Manifold* manifold, void* context)</summary>
    private BindingType PreSolveCallbackType => new BindingType.Callback(
        [("shapeIdA", HandleType("b2ShapeId")),
         ("shapeIdB", HandleType("b2ShapeId")),
         ("manifold", ManifoldPtrType)],
        new BindingType.Bool());

    /// <summary>b2CustomFilterFcn: bool callback(b2ShapeId shapeIdA, b2ShapeId shapeIdB, void* context)</summary>
    private BindingType CustomFilterCallbackType => new BindingType.Callback(
        [("shapeIdA", HandleType("b2ShapeId")),
         ("shapeIdB", HandleType("b2ShapeId"))],
        new BindingType.Bool());

    /// <summary>b2PlaneResultFcn: bool callback(b2ShapeId shapeId, b2PlaneResult* planeResult, void* context)</summary>
    private BindingType PlaneResultCallbackType => new BindingType.Callback(
        [("shapeId", HandleType("b2ShapeId")),
         ("planeResult", new BindingType.Struct("b2PlaneResult", "b2d.PlaneResult", "b2d.PlaneResult"))],
        new BindingType.Bool());

    /// <summary>Persistent コールバック型名の判別用</summary>
    private static readonly HashSet<string> PersistentCallbackTypeNames = ["b2PreSolveFcn", "b2CustomFilterFcn"];

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
        // Callback setters (handled via ExtraCCode — no void* context)
        // Query functions (need Lua callback wrappers → ExtraCCode or CallbackBridge)
        "b2World_CollideMover",
        // Array output functions → ExtraCCode / ArrayAdapter
        "b2Body_GetShapes", "b2Body_GetJoints", "b2Body_GetContactData",
        "b2Shape_GetContactData", "b2Shape_GetSensorOverlaps",
        "b2Chain_GetSegments",
        // Output param functions → handled via manual IsOutput FuncBinding (skip auto-gen)
        "b2Joint_GetConstraintTuning",
        // Event functions → EventAdapter
        // (b2World_GetBodyEvents, b2World_GetSensorEvents, b2World_GetContactEvents are now auto-generated)
        // DefaultWorldDef → PostCallPatch
        "b2DefaultWorldDef",
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
        "b2TreeStats",
        // Collision internals
        "b2ManifoldPoint", "b2Manifold", "b2ContactData",
        "b2SimplexCache", "b2Simplex", "b2SimplexVertex",
        "b2DistanceInput", "b2DistanceOutput",
        "b2SegmentDistanceResult",
        "b2ShapeCastPairInput",
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
        "b2Version", "b2Profile", "b2Counters",
        "b2Sweep", "b2TOIInput", "b2TOIOutput",
        "b2PlaneResult", "b2CollisionPlane", "b2PlaneSolverResult",
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
        "b2BodyType", "b2ShapeType", "b2JointType", "b2TOIState",
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
            Types.Ptr(Types.StructRef("b2PreSolveFcn")) => PreSolveCallbackType,
            Types.Ptr(Types.StructRef("b2CustomFilterFcn")) => CustomFilterCallbackType,
            Types.ConstPtr(Types.String) => new BindingType.Str(),
            Types.ConstPtr(Types.StructRef("b2Vec2")) => B2Vec2ArrayType,
            Types.ConstPtr(var inner) => new BindingType.ConstPtr(Resolve(inner)),
            Types.Ptr(var inner) => new BindingType.Ptr(Resolve(inner)),
            // Box2D math types → Custom
            Types.StructRef("b2Vec2") => B2Vec2Type,
            Types.StructRef("b2Rot") => B2RotType,
            Types.StructRef("b2Transform") => B2TransformType,
            Types.StructRef("b2AABB") => B2AABBType,
            Types.StructRef("b2Plane") => B2PlaneType,
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
                IsHandleType: isHandle,
                Properties: s.Name == "b2ChainDef" ? ChainDefProperties() : null));
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
                    var mode = p.ParsedType is Types.Ptr(Types.StructRef(var cbTypeName))
                        && PersistentCallbackTypeNames.Contains(cbTypeName)
                        ? CallbackBridgeMode.Persistent
                        : CallbackBridgeMode.Immediate;
                    parms.Add(new ParamBinding(p.Name, pt,
                        IsOptional: mode == CallbackBridgeMode.Persistent,
                        CallbackBridge: mode));
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

        // ===== Manual FuncBindings (IsOutput) =====
        funcs.Add(new FuncBinding(
            "b2Joint_GetConstraintTuning", "joint_get_constraint_tuning",
            [new ParamBinding("jointId", HandleType("b2JointId")),
             new ParamBinding("hertz", new BindingType.Float(), IsOutput: true),
             new ParamBinding("dampingRatio", new BindingType.Float(), IsOutput: true)],
            new BindingType.Void(), null));

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
            ("manifold_point_count", "l_b2d_manifold_point_count"),
            ("manifold_point", "l_b2d_manifold_point"),
            ("manifold_normal", "l_b2d_manifold_normal"),
            ("world_set_friction_callback", "l_b2d_world_set_friction_callback"),
            ("world_set_restitution_callback", "l_b2d_world_set_restitution_callback"),
            ("world_collide_mover", "l_b2d_world_collide_mover"),
            ("clip_vector", "l_b2d_clip_vector"),
            ("solve_planes", "l_b2d_solve_planes"),
        };

        var frictionCbType = new BindingType.Callback(
            [("frictionA", new BindingType.Float()), ("userMaterialIdA", new BindingType.Int()),
             ("frictionB", new BindingType.Float()), ("userMaterialIdB", new BindingType.Int())],
            new BindingType.Float());

        var extraLuaFuncs = new List<FuncBinding>
        {
            new("l_b2d_manifold_point_count", "manifold_point_count",
                [new ParamBinding("manifold", ManifoldPtrType)],
                new BindingType.Int(), null),
            new("l_b2d_manifold_point", "manifold_point",
                [new ParamBinding("manifold", ManifoldPtrType),
                 new ParamBinding("index", new BindingType.Int())],
                B2Vec2Type, null),
            new("l_b2d_manifold_normal", "manifold_normal",
                [new ParamBinding("manifold", ManifoldPtrType)],
                B2Vec2Type, null),
            new("l_b2d_world_set_friction_callback", "world_set_friction_callback",
                [new ParamBinding("worldId", HandleType("b2WorldId")),
                 new ParamBinding("callback", frictionCbType, IsOptional: true)],
                new BindingType.Void(), null),
            new("l_b2d_world_set_restitution_callback", "world_set_restitution_callback",
                [new ParamBinding("worldId", HandleType("b2WorldId")),
                 new ParamBinding("callback", frictionCbType, IsOptional: true)],
                new BindingType.Void(), null),
            new("l_b2d_world_collide_mover", "world_collide_mover",
                [new ParamBinding("worldId", HandleType("b2WorldId")),
                 new ParamBinding("mover", new BindingType.ConstPtr(
                     new BindingType.Struct("b2Capsule", "b2d.Capsule", "b2d.Capsule"))),
                 new ParamBinding("filter", new BindingType.Struct("b2QueryFilter", "b2d.QueryFilter", "b2d.QueryFilter")),
                 new ParamBinding("fcn", PlaneResultCallbackType)],
                new BindingType.Void(), null),
            new("l_b2d_clip_vector", "clip_vector",
                [new ParamBinding("vector", B2Vec2Type),
                 new ParamBinding("planes", new BindingType.FixedArray(
                     new BindingType.Struct("b2CollisionPlane", "b2d.CollisionPlane", "b2d.CollisionPlane"), 0))],
                B2Vec2Type, null),
            new("l_b2d_solve_planes", "solve_planes",
                [new ParamBinding("targetDelta", B2Vec2Type),
                 new ParamBinding("planes", new BindingType.FixedArray(
                     new BindingType.Struct("b2CollisionPlane", "b2d.CollisionPlane", "b2d.CollisionPlane"), 0))],
                new BindingType.Struct("b2PlaneSolverResult", "b2d.PlaneSolverResult", "b2d.PlaneSolverResult"), null),
        };

        // ===== PostCallPatch: b2DefaultWorldDef =====
        funcs.Add(new FuncBinding(
            "b2DefaultWorldDef", "default_world_def", [],
            new BindingType.Struct("b2WorldDef", "b2d.WorldDef", "b2d.WorldDef"), null,
            PostCallPatches:
            [
                new PostCallPatch("enqueueTask", "(b2EnqueueTaskCallback*)b2d_enqueue_task"),
                new PostCallPatch("finishTask", "b2d_finish_task"),
            ]));

        var arrayAdapters = new List<ArrayAdapterBinding>
        {
            new("body_get_shapes", "b2Body_GetShapeCount", "b2Body_GetShapes",
                [new ParamBinding("bodyId", HandleType("b2BodyId"))],
                HandleType("b2ShapeId")),
            new("body_get_joints", "b2Body_GetJointCount", "b2Body_GetJoints",
                [new ParamBinding("bodyId", HandleType("b2BodyId"))],
                HandleType("b2JointId")),
            new("shape_get_sensor_overlaps", "b2Shape_GetSensorCapacity", "b2Shape_GetSensorOverlaps",
                [new ParamBinding("shapeId", HandleType("b2ShapeId"))],
                HandleType("b2ShapeId")),
            new("chain_get_segments", "b2Chain_GetSegmentCount", "b2Chain_GetSegments",
                [new ParamBinding("chainId", HandleType("b2ChainId"))],
                HandleType("b2ShapeId")),
        };

        // ===== EventAdapters =====
        var eventAdapters = new List<EventAdapterBinding>
        {
            new("world_get_contact_events", "b2World_GetContactEvents", "b2ContactEvents",
                [new ParamBinding("worldId", HandleType("b2WorldId"))],
                [
                    new EventArrayField("begin_events", "beginEvents", "beginCount",
                    [
                        new EventElementField("shape_id_a", "shapeIdA", HandleType("b2ShapeId")),
                        new EventElementField("shape_id_b", "shapeIdB", HandleType("b2ShapeId")),
                    ]),
                    new EventArrayField("end_events", "endEvents", "endCount",
                    [
                        new EventElementField("shape_id_a", "shapeIdA", HandleType("b2ShapeId")),
                        new EventElementField("shape_id_b", "shapeIdB", HandleType("b2ShapeId")),
                    ]),
                    new EventArrayField("hit_events", "hitEvents", "hitCount",
                    [
                        new EventElementField("shape_id_a", "shapeIdA", HandleType("b2ShapeId")),
                        new EventElementField("shape_id_b", "shapeIdB", HandleType("b2ShapeId")),
                        new EventElementField("point", "point", B2Vec2Type),
                        new EventElementField("normal", "normal", B2Vec2Type),
                        new EventElementField("approach_speed", "approachSpeed", new BindingType.Float()),
                    ]),
                ]),
            new("world_get_sensor_events", "b2World_GetSensorEvents", "b2SensorEvents",
                [new ParamBinding("worldId", HandleType("b2WorldId"))],
                [
                    new EventArrayField("begin_events", "beginEvents", "beginCount",
                    [
                        new EventElementField("sensor_shape_id", "sensorShapeId", HandleType("b2ShapeId")),
                        new EventElementField("visitor_shape_id", "visitorShapeId", HandleType("b2ShapeId")),
                    ]),
                    new EventArrayField("end_events", "endEvents", "endCount",
                    [
                        new EventElementField("sensor_shape_id", "sensorShapeId", HandleType("b2ShapeId")),
                        new EventElementField("visitor_shape_id", "visitorShapeId", HandleType("b2ShapeId")),
                    ]),
                ]),
            new("world_get_body_events", "b2World_GetBodyEvents", "b2BodyEvents",
                [new ParamBinding("worldId", HandleType("b2WorldId"))],
                [
                    new EventArrayField("move_events", "moveEvents", "moveCount",
                    [
                        new EventElementField("transform", "transform", B2TransformType),
                        new EventElementField("body_id", "bodyId", HandleType("b2BodyId")),
                        new EventElementField("fell_asleep", "fellAsleep", new BindingType.Bool()),
                    ]),
                ]),
        };

        return new ModuleSpec(
            ModuleName, Prefix,
            ["box2d/box2d.h", "box2d/math_functions.h", "box2d/collision.h"],
            ExtraCCode(),
            structs, funcs, enums,
            extraRegs,
            [],
            ExtraLuaFuncs: extraLuaFuncs,
            ArrayAdapters: arrayAdapters,
            EventAdapters: eventAdapters);
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
        name.StartsWith("b2TimeOfImpact") ||
        name.StartsWith("b2GetVersion") ||
        name.StartsWith("b2GetTicks") ||
        name.StartsWith("b2GetMilliseconds") ||
        name.StartsWith("b2GetByteCount") ||
        name == "b2Atan2" ||
        name == "b2ComputeCosSin" ||
        name == "b2SetLengthUnitsPerMeter" ||
        name == "b2GetLengthUnitsPerMeter";

    // ===== ChainDef PropertyBindings =====

    private static List<PropertyBinding> ChainDefProperties() =>
    [
        new PropertyBinding("points", B2Vec2ArrayType,
            // Getter: C array → Lua table of {x,y}
            """
            int _count = {self}->count;
                    const b2Vec2* _pts = {self}->points;
                    if (_pts == NULL) { lua_pushnil(L); } else {
                        lua_createtable(L, _count, 0);
                        for (int _i = 0; _i < _count; _i++) {
                            lua_createtable(L, 2, 0);
                            lua_pushnumber(L, _pts[_i].x); lua_rawseti(L, -2, 1);
                            lua_pushnumber(L, _pts[_i].y); lua_rawseti(L, -2, 2);
                            lua_rawseti(L, -2, _i + 1);
                        }
                    }
            """,
            // Setter: Lua table → allocated b2Vec2 array, uservalue slot 2
            """
            int _n = (int)lua_rawlen(L, {value_idx});
                    b2Vec2* _pts = (b2Vec2*)lua_newuserdatauv(L, sizeof(b2Vec2) * (_n > 0 ? _n : 1), 0);
                    for (int _i = 0; _i < _n; _i++) {
                        lua_rawgeti(L, {value_idx}, _i + 1);
                        lua_rawgeti(L, -1, 1); _pts[_i].x = (float)lua_tonumber(L, -1); lua_pop(L, 1);
                        lua_rawgeti(L, -1, 2); _pts[_i].y = (float)lua_tonumber(L, -1); lua_pop(L, 1);
                        lua_pop(L, 1);
                    }
                    lua_setiuservalue(L, 1, 2);
                    {self}->points = _pts;
                    {self}->count = _n
            """),
        new PropertyBinding("materials",
            new BindingType.FixedArray(
                new BindingType.Struct("b2SurfaceMaterial", "b2d.SurfaceMaterial", "b2d.SurfaceMaterial"), 0),
            // Getter: C array → Lua table of b2SurfaceMaterial userdata
            """
            int _count = {self}->materialCount;
                    const b2SurfaceMaterial* _mats = {self}->materials;
                    if (_mats == NULL) { lua_pushnil(L); } else {
                        lua_createtable(L, _count, 0);
                        for (int _i = 0; _i < _count; _i++) {
                            b2SurfaceMaterial* _ud = (b2SurfaceMaterial*)lua_newuserdatauv(L, sizeof(b2SurfaceMaterial), 1);
                            *_ud = _mats[_i];
                            luaL_setmetatable(L, "b2d.SurfaceMaterial");
                            lua_rawseti(L, -2, _i + 1);
                        }
                    }
            """,
            // Setter: Lua table of b2SurfaceMaterial → allocated array, uservalue slot 3
            """
            int _n = (int)lua_rawlen(L, {value_idx});
                    b2SurfaceMaterial* _mats = (b2SurfaceMaterial*)lua_newuserdatauv(L, sizeof(b2SurfaceMaterial) * (_n > 0 ? _n : 1), 0);
                    for (int _i = 0; _i < _n; _i++) {
                        lua_rawgeti(L, {value_idx}, _i + 1);
                        b2SurfaceMaterial* _src = (b2SurfaceMaterial*)luaL_checkudata(L, -1, "b2d.SurfaceMaterial");
                        _mats[_i] = *_src;
                        lua_pop(L, 1);
                    }
                    lua_setiuservalue(L, 1, 3);
                    {self}->materials = _mats;
                    {self}->materialCount = _n
            """),
    ];

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

        /* Manifold accessors for PreSolve callback */
        static int l_b2d_manifold_point_count(lua_State *L) {
            b2Manifold* m = (b2Manifold*)lua_touserdata(L, 1);
            lua_pushinteger(L, m->pointCount);
            return 1;
        }
        static int l_b2d_manifold_point(lua_State *L) {
            b2Manifold* m = (b2Manifold*)lua_touserdata(L, 1);
            int i = (int)luaL_checkinteger(L, 2) - 1;
            lua_newtable(L);
            lua_pushnumber(L, m->points[i].point.x); lua_rawseti(L, -2, 1);
            lua_pushnumber(L, m->points[i].point.y); lua_rawseti(L, -2, 2);
            return 1;
        }
        static int l_b2d_manifold_normal(lua_State *L) {
            b2Manifold* m = (b2Manifold*)lua_touserdata(L, 1);
            lua_newtable(L);
            lua_pushnumber(L, m->normal.x); lua_rawseti(L, -2, 1);
            lua_pushnumber(L, m->normal.y); lua_rawseti(L, -2, 2);
            return 1;
        }

        /* Friction callback (no void* context — manual trampoline) */
        static lua_State* _friction_cb_L = NULL;
        static int _friction_cb_ref = LUA_NOREF;

        static float b2d_friction_trampoline(float frictionA, int matIdA, float frictionB, int matIdB) {
            if (!_friction_cb_L || _friction_cb_ref == LUA_NOREF)
                return frictionA * frictionB;
            lua_rawgeti(_friction_cb_L, LUA_REGISTRYINDEX, _friction_cb_ref);
            lua_pushnumber(_friction_cb_L, frictionA);
            lua_pushinteger(_friction_cb_L, matIdA);
            lua_pushnumber(_friction_cb_L, frictionB);
            lua_pushinteger(_friction_cb_L, matIdB);
            lua_call(_friction_cb_L, 4, 1);
            float r = (float)lua_tonumber(_friction_cb_L, -1);
            lua_pop(_friction_cb_L, 1);
            return r;
        }

        static int l_b2d_world_set_friction_callback(lua_State *L) {
            b2WorldId worldId = *(b2WorldId*)luaL_checkudata(L, 1, "b2d.WorldId");
            if (lua_isnil(L, 2) || lua_isnone(L, 2)) {
                if (_friction_cb_ref != LUA_NOREF) {
                    luaL_unref(L, LUA_REGISTRYINDEX, _friction_cb_ref);
                    _friction_cb_ref = LUA_NOREF; _friction_cb_L = NULL;
                }
                b2World_SetFrictionCallback(worldId, NULL);
            } else {
                luaL_checktype(L, 2, LUA_TFUNCTION);
                if (_friction_cb_ref != LUA_NOREF)
                    luaL_unref(L, LUA_REGISTRYINDEX, _friction_cb_ref);
                lua_pushvalue(L, 2);
                _friction_cb_ref = luaL_ref(L, LUA_REGISTRYINDEX);
                _friction_cb_L = L;
                b2World_SetFrictionCallback(worldId, b2d_friction_trampoline);
            }
            return 0;
        }

        /* Restitution callback (no void* context — manual trampoline) */
        static lua_State* _restitution_cb_L = NULL;
        static int _restitution_cb_ref = LUA_NOREF;

        static float b2d_restitution_trampoline(float restitutionA, int matIdA, float restitutionB, int matIdB) {
            if (!_restitution_cb_L || _restitution_cb_ref == LUA_NOREF)
                return restitutionA > restitutionB ? restitutionA : restitutionB;
            lua_rawgeti(_restitution_cb_L, LUA_REGISTRYINDEX, _restitution_cb_ref);
            lua_pushnumber(_restitution_cb_L, restitutionA);
            lua_pushinteger(_restitution_cb_L, matIdA);
            lua_pushnumber(_restitution_cb_L, restitutionB);
            lua_pushinteger(_restitution_cb_L, matIdB);
            lua_call(_restitution_cb_L, 4, 1);
            float r = (float)lua_tonumber(_restitution_cb_L, -1);
            lua_pop(_restitution_cb_L, 1);
            return r;
        }

        static int l_b2d_world_set_restitution_callback(lua_State *L) {
            b2WorldId worldId = *(b2WorldId*)luaL_checkudata(L, 1, "b2d.WorldId");
            if (lua_isnil(L, 2) || lua_isnone(L, 2)) {
                if (_restitution_cb_ref != LUA_NOREF) {
                    luaL_unref(L, LUA_REGISTRYINDEX, _restitution_cb_ref);
                    _restitution_cb_ref = LUA_NOREF; _restitution_cb_L = NULL;
                }
                b2World_SetRestitutionCallback(worldId, NULL);
            } else {
                luaL_checktype(L, 2, LUA_TFUNCTION);
                if (_restitution_cb_ref != LUA_NOREF)
                    luaL_unref(L, LUA_REGISTRYINDEX, _restitution_cb_ref);
                lua_pushvalue(L, 2);
                _restitution_cb_ref = luaL_ref(L, LUA_REGISTRYINDEX);
                _restitution_cb_L = L;
                b2World_SetRestitutionCallback(worldId, b2d_restitution_trampoline);
            }
            return 0;
        }

        /* CollideMover callback trampoline (immediate — valid only during call) */
        static lua_State* _collide_mover_cb_L = NULL;
        static int _collide_mover_cb_ref = LUA_NOREF;

        static bool b2d_collide_mover_trampoline(b2ShapeId shapeId, const b2PlaneResult* plane, void* context) {
            (void)context;
            if (!_collide_mover_cb_L || _collide_mover_cb_ref == LUA_NOREF) return false;
            lua_rawgeti(_collide_mover_cb_L, LUA_REGISTRYINDEX, _collide_mover_cb_ref);
            b2ShapeId* sid = (b2ShapeId*)lua_newuserdatauv(_collide_mover_cb_L, sizeof(b2ShapeId), 1);
            *sid = shapeId;
            luaL_setmetatable(_collide_mover_cb_L, "b2d.ShapeId");
            b2PlaneResult* pr = (b2PlaneResult*)lua_newuserdatauv(_collide_mover_cb_L, sizeof(b2PlaneResult), 1);
            *pr = *plane;
            luaL_setmetatable(_collide_mover_cb_L, "b2d.PlaneResult");
            lua_call(_collide_mover_cb_L, 2, 1);
            bool r = lua_toboolean(_collide_mover_cb_L, -1);
            lua_pop(_collide_mover_cb_L, 1);
            return r;
        }

        static int l_b2d_world_collide_mover(lua_State *L) {
            b2WorldId worldId = *(b2WorldId*)luaL_checkudata(L, 1, "b2d.WorldId");
            const b2Capsule* mover = (const b2Capsule*)luaL_checkudata(L, 2, "b2d.Capsule");
            b2QueryFilter filter = *(b2QueryFilter*)luaL_checkudata(L, 3, "b2d.QueryFilter");
            luaL_checktype(L, 4, LUA_TFUNCTION);
            lua_pushvalue(L, 4);
            _collide_mover_cb_ref = luaL_ref(L, LUA_REGISTRYINDEX);
            _collide_mover_cb_L = L;
            b2World_CollideMover(worldId, mover, filter, b2d_collide_mover_trampoline, NULL);
            luaL_unref(L, LUA_REGISTRYINDEX, _collide_mover_cb_ref);
            _collide_mover_cb_ref = LUA_NOREF;
            _collide_mover_cb_L = NULL;
            return 0;
        }

        /* b2ClipVector wrapper (takes array of b2CollisionPlane userdata) */
        static int l_b2d_clip_vector(lua_State *L) {
            luaL_checktype(L, 1, LUA_TTABLE);
            b2Vec2 vector;
            lua_rawgeti(L, 1, 1); vector.x = (float)lua_tonumber(L, -1); lua_pop(L, 1);
            lua_rawgeti(L, 1, 2); vector.y = (float)lua_tonumber(L, -1); lua_pop(L, 1);
            luaL_checktype(L, 2, LUA_TTABLE);
            int count = (int)lua_rawlen(L, 2);
            b2CollisionPlane planes[64];
            luaL_argcheck(L, count <= 64, 2, "too many planes (max 64)");
            for (int i = 0; i < count; i++) {
                lua_rawgeti(L, 2, i + 1);
                b2CollisionPlane* p = (b2CollisionPlane*)luaL_checkudata(L, -1, "b2d.CollisionPlane");
                planes[i] = *p;
                lua_pop(L, 1);
            }
            b2Vec2 result = b2ClipVector(vector, planes, count);
            lua_newtable(L);
            lua_pushnumber(L, result.x); lua_rawseti(L, -2, 1);
            lua_pushnumber(L, result.y); lua_rawseti(L, -2, 2);
            return 1;
        }

        /* b2SolvePlanes wrapper (takes array of b2CollisionPlane userdata, mutates push field) */
        static int l_b2d_solve_planes(lua_State *L) {
            luaL_checktype(L, 1, LUA_TTABLE);
            b2Vec2 targetDelta;
            lua_rawgeti(L, 1, 1); targetDelta.x = (float)lua_tonumber(L, -1); lua_pop(L, 1);
            lua_rawgeti(L, 1, 2); targetDelta.y = (float)lua_tonumber(L, -1); lua_pop(L, 1);
            luaL_checktype(L, 2, LUA_TTABLE);
            int count = (int)lua_rawlen(L, 2);
            b2CollisionPlane planes[64];
            luaL_argcheck(L, count <= 64, 2, "too many planes (max 64)");
            for (int i = 0; i < count; i++) {
                lua_rawgeti(L, 2, i + 1);
                b2CollisionPlane* p = (b2CollisionPlane*)luaL_checkudata(L, -1, "b2d.CollisionPlane");
                planes[i] = *p;
                lua_pop(L, 1);
            }
            b2PlaneSolverResult result = b2SolvePlanes(targetDelta, planes, count);
            for (int i = 0; i < count; i++) {
                lua_rawgeti(L, 2, i + 1);
                b2CollisionPlane* p = (b2CollisionPlane*)lua_touserdata(L, -1);
                *p = planes[i];
                lua_pop(L, 1);
            }
            b2PlaneSolverResult* ud = (b2PlaneSolverResult*)lua_newuserdatauv(L, sizeof(b2PlaneSolverResult), 1);
            *ud = result;
            luaL_setmetatable(L, "b2d.PlaneSolverResult");
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
