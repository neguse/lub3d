using Generator;
using Generator.CBinding;
using Generator.LuaCats;
using Generator.WebIdl;

namespace Generator.Tests;

public class WebIdlBox2dTests
{
    // ─── Step 1: Parser tests ───

    [Fact]
    public void Parse_Callback_Simple()
    {
        var file = WebIdlParser.ParseFile("""
            callback b2OverlapResultFcn = boolean (b2ShapeId shapeId);
            """);
        Assert.Single(file.Callbacks);
        var cb = file.Callbacks[0];
        Assert.Equal("b2OverlapResultFcn", cb.CName);
        Assert.Equal("boolean", cb.ReturnType.Name);
        Assert.Single(cb.Params);
        Assert.Equal("shapeId", cb.Params[0].Name);
        Assert.Equal("b2ShapeId", cb.Params[0].Type.Name);
    }

    [Fact]
    public void Parse_Callback_MultipleParams()
    {
        var file = WebIdlParser.ParseFile("""
            callback b2CastResultFcn = float (b2ShapeId shapeId, b2Vec2 point, b2Vec2 normal, float fraction);
            """);
        var cb = file.Callbacks[0];
        Assert.Equal("b2CastResultFcn", cb.CName);
        Assert.Equal("float", cb.ReturnType.Name);
        Assert.Equal(4, cb.Params.Count);
    }

    [Fact]
    public void Parse_Callback_WithExtAttrs()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="b2"]

            [Persistent]
            callback b2PreSolveFcn = boolean (b2ShapeId shapeIdA, b2ShapeId shapeIdB, VoidPtr manifold);
            """);
        var cb = file.Callbacks[0];
        Assert.Equal("b2PreSolveFcn", cb.CName);
        Assert.NotNull(cb.ExtAttrs);
        Assert.True(cb.ExtAttrs!.ContainsKey("Persistent"));
    }

    [Fact]
    public void Parse_EventAdapter_Simple()
    {
        var file = WebIdlParser.ParseFile("""
            event world_get_contact_events(b2WorldId worldId) : b2ContactEvents {
                begin_events(beginEvents, beginCount) {
                    b2ShapeId shape_id_a = shapeIdA;
                    b2ShapeId shape_id_b = shapeIdB;
                };
            };
            """);
        Assert.Single(file.EventAdapters);
        var ev = file.EventAdapters[0];
        Assert.Equal("world_get_contact_events", ev.LuaName);
        Assert.Equal("b2ContactEvents", ev.CReturnType);
        Assert.Single(ev.Params);
        Assert.Equal("worldId", ev.Params[0].Name);
        Assert.Single(ev.Arrays);
        Assert.Equal("begin_events", ev.Arrays[0].LuaFieldName);
        Assert.Equal("beginEvents", ev.Arrays[0].CArrayAccessor);
        Assert.Equal("beginCount", ev.Arrays[0].CCountAccessor);
        Assert.Equal(2, ev.Arrays[0].Fields.Count);
        Assert.Equal("shape_id_a", ev.Arrays[0].Fields[0].LuaName);
        Assert.Equal("shapeIdA", ev.Arrays[0].Fields[0].CAccessor);
    }

    [Fact]
    public void Parse_EventAdapter_MultipleArrays()
    {
        var file = WebIdlParser.ParseFile("""
            event world_get_contact_events(b2WorldId worldId) : b2ContactEvents {
                begin_events(beginEvents, beginCount) {
                    b2ShapeId shape_id_a = shapeIdA;
                };
                hit_events(hitEvents, hitCount) {
                    b2ShapeId shape_id_a = shapeIdA;
                    float approach_speed = approachSpeed;
                };
            };
            """);
        var ev = file.EventAdapters[0];
        Assert.Equal(2, ev.Arrays.Count);
        Assert.Equal("hit_events", ev.Arrays[1].LuaFieldName);
        Assert.Equal(2, ev.Arrays[1].Fields.Count);
    }

    [Fact]
    public void Parse_FieldExtAttrs_Ignore()
    {
        var file = WebIdlParser.ParseFile("""
            dictionary b2WorldDef {
                [Ignore] VoidPtr userData;
                float gravity_x;
            };
            """);
        Assert.Equal(2, file.Dictionaries[0].Fields.Count);
        Assert.NotNull(file.Dictionaries[0].Fields[0].ExtAttrs);
        Assert.True(file.Dictionaries[0].Fields[0].ExtAttrs!.ContainsKey("Ignore"));
        Assert.Null(file.Dictionaries[0].Fields[1].ExtAttrs);
    }

    [Fact]
    public void Parse_MixedDefinitions()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="b2", CInclude="box2d/box2d.h"]

            callback b2OverlapResultFcn = boolean (b2ShapeId shapeId);

            [HandleType]
            dictionary b2WorldId {
                unsigned short index1;
                unsigned short revision;
            };

            enum b2BodyType {
                "b2_staticBody" = 0,
                "b2_kinematicBody" = 1,
            };

            namespace b2d {
                void World_Step(b2WorldId worldId, float timeStep, long subStepCount);
            };

            event world_get_body_events(b2WorldId worldId) : b2BodyEvents {
                move_events(moveEvents, moveCount) {
                    b2BodyId body_id = bodyId;
                };
            };
            """);
        Assert.Equal("b2", file.ExtAttrs["Prefix"]);
        Assert.Single(file.Callbacks);
        Assert.Single(file.Dictionaries);
        Assert.Single(file.Enums);
        Assert.NotNull(file.Namespace);
        Assert.Single(file.EventAdapters);
    }

    // ─── Step 2: Converter - ValueStruct + HandleType ───

    [Fact]
    public void Convert_ValueStruct_ScalarFields()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="b2"]

            [ValueStruct]
            dictionary b2Vec2 { float x; float y; };

            namespace b2d {
                b2Vec2 GetPosition(float a);
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "b2d");
        // ValueStruct dictionaries should NOT produce StructBindings
        Assert.Empty(spec.Structs);
        // Function returning ValueStruct
        var func = spec.Funcs.First(f => f.LuaName == "GetPosition");
        Assert.IsType<BindingType.ValueStruct>(func.ReturnType);
        var vs = (BindingType.ValueStruct)func.ReturnType;
        Assert.Equal("b2Vec2", vs.CTypeName);
        Assert.True(vs.Settable);
        Assert.Equal(2, vs.Fields.Count);
        Assert.IsType<BindingType.ScalarField>(vs.Fields[0]);
        Assert.Equal("x", vs.Fields[0].CAccessor);
    }

    [Fact]
    public void Convert_ValueStruct_ReadOnly()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="b2"]

            [ValueStruct, ReadOnly]
            dictionary b2CosSin { float cosine; float sine; };

            namespace b2d {
                b2CosSin ComputeCosSin(float angle);
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "b2d");
        var func = spec.Funcs.First();
        var vs = (BindingType.ValueStruct)func.ReturnType;
        Assert.False(vs.Settable);
    }

    [Fact]
    public void Convert_ValueStruct_Nested()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="b2"]

            [ValueStruct, ReadOnly, Nested="p:x+y,q:c+s"]
            dictionary b2Transform {};

            namespace b2d {
                b2Transform GetTransform(float a);
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "b2d");
        var func = spec.Funcs.First();
        var vs = (BindingType.ValueStruct)func.ReturnType;
        Assert.Equal("b2Transform", vs.CTypeName);
        Assert.Equal("number[][]", vs.LuaCatsType);
        Assert.False(vs.Settable);
        Assert.Equal(2, vs.Fields.Count);
        Assert.IsType<BindingType.NestedFields>(vs.Fields[0]);
        var nested = (BindingType.NestedFields)vs.Fields[0];
        Assert.Equal("p", nested.CAccessor);
        Assert.Equal(["x", "y"], nested.SubAccessors);
    }

    [Fact]
    public void Convert_HandleType_CreatesStruct()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="b2"]

            [HandleType]
            dictionary b2WorldId {
                unsigned short index1;
                unsigned short revision;
            };

            namespace b2d {
                void DestroyWorld(b2WorldId worldId);
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "b2d");
        Assert.Single(spec.Structs);
        var s = spec.Structs[0];
        Assert.Equal("b2WorldId", s.CName);
        Assert.True(s.IsHandleType);
        Assert.False(s.HasMetamethods);
        // HandleType param in function
        var func = spec.Funcs.First();
        Assert.IsType<BindingType.Struct>(func.Params[0].Type);
    }

    [Fact]
    public void Convert_FieldIgnore()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="b2"]

            [HasMetamethods]
            dictionary b2WorldDef {
                [Ignore] Callback enqueueTask;
                [Ignore] VoidPtr userData;
                float gravity_x;
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "b2d");
        var s = spec.Structs.First(s => s.CName == "b2WorldDef");
        Assert.Single(s.Fields); // only gravity_x
        Assert.Equal("gravity_x", s.Fields[0].CName);
    }

    [Fact]
    public void Convert_CamelCase_Dictionary()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="b2"]

            [CamelCase, HasMetamethods]
            dictionary b2BodyDef {
                float linearDamping;
                boolean fixedRotation;
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "b2d");
        var s = spec.Structs.First();
        Assert.Equal("linearDamping", s.Fields[0].CName);
        Assert.Equal("linear_damping", s.Fields[0].LuaName);
        Assert.Equal("fixedRotation", s.Fields[1].CName);
        Assert.Equal("fixed_rotation", s.Fields[1].LuaName);
    }

    [Fact]
    public void Convert_MultipleCIncludes()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="b2", CInclude="box2d/box2d.h,box2d/math_functions.h,box2d/collision.h"]
            namespace b2d { void setup(); };
            """);
        var spec = WebIdlToSpec.Convert(file, "b2d");
        Assert.Equal(3, spec.CIncludes.Count);
        Assert.Contains("box2d/box2d.h", spec.CIncludes);
        Assert.Contains("box2d/math_functions.h", spec.CIncludes);
        Assert.Contains("box2d/collision.h", spec.CIncludes);
    }

    // ─── Step 3: Converter - Callback + FuncNaming + その他 ExtAttr ───

    [Fact]
    public void Convert_Callback_ParamType()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="b2"]

            [HandleType]
            dictionary b2ShapeId { unsigned short index1; };

            callback b2OverlapResultFcn = boolean (b2ShapeId shapeId);

            namespace b2d {
                void World_OverlapAABB(b2OverlapResultFcn fcn, VoidPtr context);
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "b2d");
        var func = spec.Funcs.First();
        // callback param
        Assert.Single(func.Params); // void* context should be auto-removed
        Assert.IsType<BindingType.Callback>(func.Params[0].Type);
        Assert.Equal(CallbackBridgeMode.Immediate, func.Params[0].CallbackBridge);
    }

    [Fact]
    public void Convert_Callback_Persistent()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="b2"]

            [HandleType]
            dictionary b2ShapeId { unsigned short index1; };
            [HandleType]
            dictionary b2WorldId { unsigned short index1; };

            [Persistent]
            callback b2PreSolveFcn = boolean (b2ShapeId shapeIdA, b2ShapeId shapeIdB, VoidPtr manifold);

            namespace b2d {
                void World_SetPreSolveCallback(b2WorldId worldId, b2PreSolveFcn fcn, VoidPtr context);
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "b2d");
        var func = spec.Funcs.First();
        // worldId + fcn (context auto-removed)
        Assert.Equal(2, func.Params.Count);
        Assert.Equal(CallbackBridgeMode.Persistent, func.Params[1].CallbackBridge);
        Assert.True(func.Params[1].IsOptional);
    }

    [Fact]
    public void Convert_PascalCase_FuncNaming()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="b2", FuncNaming="PascalCase"]

            [HandleType]
            dictionary b2WorldId { unsigned short index1; };

            namespace b2d {
                b2WorldId CreateWorld(float a);
                void World_Step(b2WorldId worldId, float timeStep, long subStepCount);
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "b2d");
        // CName should use prefix + PascalCase name
        var create = spec.Funcs.First(f => f.CName == "b2CreateWorld");
        Assert.Equal("create_world", create.LuaName);
        var step = spec.Funcs.First(f => f.CName == "b2World_Step");
        Assert.Equal("world_step", step.LuaName);
    }

    [Fact]
    public void Convert_EnumItemStyle_CamelCase()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="b2"]

            [EnumItemStyle="CamelCase"]
            enum b2BodyType {
                "b2_staticBody" = 0,
                "b2_kinematicBody" = 1,
                "b2_dynamicBody" = 2,
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "b2d");
        var e = spec.Enums.First();
        Assert.Equal("STATIC_BODY", e.Items[0].LuaName);
        Assert.Equal("KINEMATIC_BODY", e.Items[1].LuaName);
        Assert.Equal("DYNAMIC_BODY", e.Items[2].LuaName);
    }

    [Fact]
    public void Convert_OutputParams()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="b2", FuncNaming="PascalCase"]

            [HandleType]
            dictionary b2JointId { unsigned short index1; };

            namespace b2d {
                [OutputParams="hertz,dampingRatio"]
                void Joint_GetConstraintTuning(b2JointId jointId, float hertz, float dampingRatio);
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "b2d");
        var func = spec.Funcs.First();
        Assert.False(func.Params[0].IsOutput); // jointId
        Assert.True(func.Params[1].IsOutput);  // hertz
        Assert.True(func.Params[2].IsOutput);  // dampingRatio
    }

    [Fact]
    public void Convert_PostCallPatch()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="b2", FuncNaming="PascalCase"]

            [HasMetamethods]
            dictionary b2WorldDef { float gravity_x; };

            namespace b2d {
                [PostCallPatch="enqueueTask:(b2EnqueueTaskCallback*)b2d_enqueue_task,finishTask:b2d_finish_task"]
                b2WorldDef DefaultWorldDef();
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "b2d");
        var func = spec.Funcs.First();
        Assert.NotNull(func.PostCallPatches);
        Assert.Equal(2, func.PostCallPatches!.Count);
        Assert.Equal("enqueueTask", func.PostCallPatches[0].FieldName);
        Assert.Equal("(b2EnqueueTaskCallback*)b2d_enqueue_task", func.PostCallPatches[0].CExpression);
    }

    [Fact]
    public void Convert_ArrayAdapter()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="b2", FuncNaming="PascalCase"]

            [HandleType]
            dictionary b2BodyId { unsigned short index1; };
            [HandleType]
            dictionary b2ShapeId { unsigned short index1; };

            namespace b2d {
                [ArrayAdapter, CountFunc="b2Body_GetShapeCount"]
                b2ShapeId Body_GetShapes(b2BodyId bodyId);
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "b2d");
        Assert.Empty(spec.Funcs); // ArrayAdapter should not be in funcs
        Assert.Single(spec.ArrayAdapters);
        var aa = spec.ArrayAdapters[0];
        Assert.Equal("body_get_shapes", aa.LuaName);
        Assert.Equal("b2Body_GetShapeCount", aa.CountFuncCName);
        Assert.Equal("b2Body_GetShapes", aa.FillFuncCName);
        Assert.IsType<BindingType.Struct>(aa.ElementType);
    }

    // ─── Step 4: Converter - EventAdapter ───

    [Fact]
    public void Convert_EventAdapter_Basic()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="b2"]

            [HandleType]
            dictionary b2WorldId { unsigned short index1; };
            [HandleType]
            dictionary b2ShapeId { unsigned short index1; };

            [CFunc="b2World_GetContactEvents"]
            event world_get_contact_events(b2WorldId worldId) : b2ContactEvents {
                begin_events(beginEvents, beginCount) {
                    b2ShapeId shape_id_a = shapeIdA;
                    b2ShapeId shape_id_b = shapeIdB;
                };
                hit_events(hitEvents, hitCount) {
                    b2ShapeId shape_id_a = shapeIdA;
                    float approach_speed = approachSpeed;
                };
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "b2d");
        Assert.Single(spec.EventAdapters);
        var ev = spec.EventAdapters[0];
        Assert.Equal("world_get_contact_events", ev.LuaName);
        Assert.Equal("b2World_GetContactEvents", ev.CFuncName);
        Assert.Equal("b2ContactEvents", ev.CReturnType);
        Assert.Single(ev.InputParams);
        Assert.Equal(2, ev.ArrayFields.Count);

        var begin = ev.ArrayFields[0];
        Assert.Equal("begin_events", begin.LuaFieldName);
        Assert.Equal("beginEvents", begin.CArrayAccessor);
        Assert.Equal("beginCount", begin.CCountAccessor);
        Assert.Equal(2, begin.ElementFields.Count);
        Assert.IsType<BindingType.Struct>(begin.ElementFields[0].Type);

        var hit = ev.ArrayFields[1];
        Assert.Equal(2, hit.ElementFields.Count);
        Assert.IsType<BindingType.Float>(hit.ElementFields[1].Type);
    }

    [Fact]
    public void Convert_EventAdapter_ValueStructField()
    {
        var file = WebIdlParser.ParseFile("""
            [Prefix="b2"]

            [ValueStruct]
            dictionary b2Vec2 { float x; float y; };

            [HandleType]
            dictionary b2WorldId { unsigned short index1; };
            [HandleType]
            dictionary b2ShapeId { unsigned short index1; };

            event world_get_contact_events(b2WorldId worldId) : b2ContactEvents {
                hit_events(hitEvents, hitCount) {
                    b2ShapeId shape_id_a = shapeIdA;
                    b2Vec2 point = point;
                };
            };
            """);
        var spec = WebIdlToSpec.Convert(file, "b2d");
        var hit = spec.EventAdapters[0].ArrayFields[0];
        Assert.IsType<BindingType.ValueStruct>(hit.ElementFields[1].Type);
    }
}
