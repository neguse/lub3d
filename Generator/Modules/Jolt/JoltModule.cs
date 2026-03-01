using Generator.ClangAst;

namespace Generator.Modules.Jolt;

/// <summary>
/// Jolt Physics Lua binding module.
/// Generator が C++ バインディングコード (gen/jolt.cpp) と LuaCATS アノテーションを自動生成する。
/// </summary>
public class JoltModule : IModule
{
    public string ModuleName => "jolt";
    public string Prefix => "jolt_";

    // Multi-return helper types (LuaCATS only)
    private static readonly BindingType Vec3Return = new BindingType.Custom(
        "void", "number, number, number", null, null, null, null);

    private static readonly BindingType QuatReturn = new BindingType.Custom(
        "void", "number, number, number, number", null, null, null, null);

    private static readonly BindingType WorldType = new BindingType.Struct(
        "JoltWorld", "jolt.World", "jolt.World");

    // ExtraCCode: Jolt ボイラープレート (includes, layer definitions, JoltWorld struct, helpers, constructor)
    private const string JoltExtraCCode = """

// Jolt includes
#include <Jolt/Jolt.h>
#include <Jolt/RegisterTypes.h>
#include <Jolt/Core/Factory.h>
#include <Jolt/Core/TempAllocator.h>
#include <Jolt/Core/JobSystemThreadPool.h>
#include <Jolt/Physics/PhysicsSettings.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Body/BodyActivationListener.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/Collision/Shape/SphereShape.h>
#include <Jolt/Physics/Collision/Shape/CapsuleShape.h>

using namespace JPH;

// ===== Layer definitions (fixed 2-layer setup) =====

namespace Layers {
    static constexpr ObjectLayer NON_MOVING = 0;
    static constexpr ObjectLayer MOVING = 1;
    static constexpr uint NUM_LAYERS = 2;
}

namespace BroadPhaseLayers {
    static constexpr BroadPhaseLayer NON_MOVING(0);
    static constexpr BroadPhaseLayer MOVING(1);
    static constexpr uint NUM_LAYERS = 2;
}

class BPLayerInterfaceImpl final : public BroadPhaseLayerInterface {
public:
    uint GetNumBroadPhaseLayers() const override { return BroadPhaseLayers::NUM_LAYERS; }
    BroadPhaseLayer GetBroadPhaseLayer(ObjectLayer inLayer) const override {
        static const BroadPhaseLayer table[] = { BroadPhaseLayers::NON_MOVING, BroadPhaseLayers::MOVING };
        return table[inLayer];
    }
#if defined(JPH_EXTERNAL_PROFILE) || defined(JPH_PROFILE_ENABLED)
    const char* GetBroadPhaseLayerName(BroadPhaseLayer inLayer) const override {
        switch ((BroadPhaseLayer::Type)inLayer) {
            case (BroadPhaseLayer::Type)0: return "NON_MOVING";
            case (BroadPhaseLayer::Type)1: return "MOVING";
            default: return "UNKNOWN";
        }
    }
#endif
};

class ObjectVsBroadPhaseLayerFilterImpl final : public ObjectVsBroadPhaseLayerFilter {
public:
    bool ShouldCollide(ObjectLayer inLayer1, BroadPhaseLayer inLayer2) const override {
        if (inLayer1 == Layers::NON_MOVING)
            return inLayer2 == BroadPhaseLayers::MOVING;
        return true;
    }
};

class ObjectLayerPairFilterImpl final : public ObjectLayerPairFilter {
public:
    bool ShouldCollide(ObjectLayer inLayer1, ObjectLayer inLayer2) const override {
        if (inLayer1 == Layers::NON_MOVING && inLayer2 == Layers::NON_MOVING)
            return false;
        return true;
    }
};

// ===== JoltWorld — single opaque type wrapping everything =====

struct JoltWorld {
    PhysicsSystem*                      physics_system;
    TempAllocatorImpl*                  temp_allocator;
    JobSystemThreadPool*                job_system;
    BPLayerInterfaceImpl*               bp_layer;
    ObjectVsBroadPhaseLayerFilterImpl*  obj_vs_bp_filter;
    ObjectLayerPairFilterImpl*          obj_pair_filter;
};

static void jolt_world_free(JoltWorld* world) {
    if (!world) return;
    delete world->physics_system;
    delete world->job_system;
    delete world->temp_allocator;
    delete world->bp_layer;
    delete world->obj_vs_bp_filter;
    delete world->obj_pair_filter;
    delete world;
}

// ===== Helper functions =====

static EMotionType motion_type_from_int(int v) {
    switch (v) {
        case 0: return EMotionType::Static;
        case 1: return EMotionType::Kinematic;
        case 2: return EMotionType::Dynamic;
        default: return EMotionType::Dynamic;
    }
}

static ObjectLayer layer_for_motion(EMotionType mt) {
    return mt == EMotionType::Static ? Layers::NON_MOVING : Layers::MOVING;
}

// ===== jolt.init() — create world =====

static bool s_jolt_registered = false;

static int l_jolt_world_new(lua_State *L) {
    if (!s_jolt_registered) {
        RegisterDefaultAllocator();
        Factory::sInstance = new Factory();
        RegisterTypes();
        s_jolt_registered = true;
    }

    JoltWorld* world = new JoltWorld();
    world->temp_allocator = new TempAllocatorImpl(10 * 1024 * 1024);
    world->job_system = new JobSystemThreadPool(2048, 8, -1);
    world->bp_layer = new BPLayerInterfaceImpl();
    world->obj_vs_bp_filter = new ObjectVsBroadPhaseLayerFilterImpl();
    world->obj_pair_filter = new ObjectLayerPairFilterImpl();

    world->physics_system = new PhysicsSystem();
    uint max_bodies = (uint)luaL_optinteger(L, 1, 1024);
    uint num_body_mutexes = 0;
    uint max_body_pairs = (uint)luaL_optinteger(L, 2, 1024);
    uint max_contact_constraints = (uint)luaL_optinteger(L, 3, 1024);
    world->physics_system->Init(
        max_bodies, num_body_mutexes, max_body_pairs, max_contact_constraints,
        *world->bp_layer, *world->obj_vs_bp_filter, *world->obj_pair_filter);

    JoltWorld** pp = (JoltWorld**)lua_newuserdatauv(L, sizeof(JoltWorld*), 0);
    *pp = world;
    luaL_setmetatable(L, "jolt.World");
    return 1;
}

""";

    public ModuleSpec BuildSpec(TypeRegistry reg, Dictionary<string, string> prefixToModule, SourceLink? sourceLink = null)
    {
        // World methods with CustomCallCode
        var worldMethods = new List<MethodBinding>
        {
            new("l_jolt_set_gravity", "set_gravity",
                [new ParamBinding("x", new BindingType.Float()),
                 new ParamBinding("y", new BindingType.Float()),
                 new ParamBinding("z", new BindingType.Float())],
                new BindingType.Void(), null,
                CustomCallCode: "    {self}->physics_system->SetGravity(Vec3({x}, {y}, {z}));",
                ReturnCount: 0),

            new("l_jolt_get_gravity", "get_gravity",
                [], new BindingType.Void(), null,
                CustomCallCode: """
                        Vec3 g = {self}->physics_system->GetGravity();
                        lua_pushnumber(L, g.GetX());
                        lua_pushnumber(L, g.GetY());
                        lua_pushnumber(L, g.GetZ());
                    """,
                ReturnCount: 3),

            new("l_jolt_update", "update",
                [new ParamBinding("dt", new BindingType.Float()),
                 new ParamBinding("collision_steps", new BindingType.Custom(
                    "int", "integer", null,
                    "    int {name} = (int)luaL_optinteger(L, {idx}, 1);", null, null),
                    IsOptional: true)],
                new BindingType.Void(), null,
                CustomCallCode: """
                        EPhysicsUpdateError err = {self}->physics_system->Update(
                            {dt}, {collision_steps}, {self}->temp_allocator, {self}->job_system);
                        lua_pushinteger(L, (lua_Integer)err);
                    """,
                ReturnCount: 1),

            new("l_jolt_optimize", "optimize",
                [], new BindingType.Void(), null,
                CustomCallCode: "    {self}->physics_system->OptimizeBroadPhase();",
                ReturnCount: 0),

            new("l_jolt_create_box", "create_box",
                [new ParamBinding("hx", new BindingType.Float()),
                 new ParamBinding("hy", new BindingType.Float()),
                 new ParamBinding("hz", new BindingType.Float()),
                 new ParamBinding("x", new BindingType.Float()),
                 new ParamBinding("y", new BindingType.Float()),
                 new ParamBinding("z", new BindingType.Float()),
                 new ParamBinding("motion_type", new BindingType.Custom(
                    "int", "integer", null,
                    "    int {name} = (int)luaL_optinteger(L, {idx}, 2);", null, null),
                    IsOptional: true)],
                new BindingType.Void(), null,
                CustomCallCode: """
                        EMotionType mt = motion_type_from_int({motion_type});
                        BoxShapeSettings shape_settings(Vec3({hx}, {hy}, {hz}));
                        ShapeSettings::ShapeResult shape_result = shape_settings.Create();
                        if (shape_result.HasError())
                            return luaL_error(L, "BoxShape creation failed: %s", shape_result.GetError().c_str());
                        BodyCreationSettings body_settings(
                            shape_result.Get(), RVec3({x}, {y}, {z}), Quat::sIdentity(), mt, layer_for_motion(mt));
                        BodyInterface& bi = {self}->physics_system->GetBodyInterface();
                        BodyID id = bi.CreateAndAddBody(body_settings, mt == EMotionType::Static ? EActivation::DontActivate : EActivation::Activate);
                        if (id.IsInvalid())
                            return luaL_error(L, "CreateAndAddBody failed");
                        lua_pushinteger(L, (lua_Integer)id.GetIndexAndSequenceNumber());
                    """,
                ReturnCount: 1),

            new("l_jolt_create_sphere", "create_sphere",
                [new ParamBinding("radius", new BindingType.Float()),
                 new ParamBinding("x", new BindingType.Float()),
                 new ParamBinding("y", new BindingType.Float()),
                 new ParamBinding("z", new BindingType.Float()),
                 new ParamBinding("motion_type", new BindingType.Custom(
                    "int", "integer", null,
                    "    int {name} = (int)luaL_optinteger(L, {idx}, 2);", null, null),
                    IsOptional: true)],
                new BindingType.Void(), null,
                CustomCallCode: """
                        EMotionType mt = motion_type_from_int({motion_type});
                        SphereShapeSettings shape_settings({radius});
                        ShapeSettings::ShapeResult shape_result = shape_settings.Create();
                        if (shape_result.HasError())
                            return luaL_error(L, "SphereShape creation failed: %s", shape_result.GetError().c_str());
                        BodyCreationSettings body_settings(
                            shape_result.Get(), RVec3({x}, {y}, {z}), Quat::sIdentity(), mt, layer_for_motion(mt));
                        BodyInterface& bi = {self}->physics_system->GetBodyInterface();
                        BodyID id = bi.CreateAndAddBody(body_settings, mt == EMotionType::Static ? EActivation::DontActivate : EActivation::Activate);
                        if (id.IsInvalid())
                            return luaL_error(L, "CreateAndAddBody failed");
                        lua_pushinteger(L, (lua_Integer)id.GetIndexAndSequenceNumber());
                    """,
                ReturnCount: 1),

            new("l_jolt_remove_body", "remove_body",
                [new ParamBinding("id", new BindingType.Int())],
                new BindingType.Void(), null,
                CustomCallCode: """
                        BodyID body_id((uint32){id});
                        BodyInterface& bi = {self}->physics_system->GetBodyInterface();
                        bi.RemoveBody(body_id);
                        bi.DestroyBody(body_id);
                    """,
                ReturnCount: 0),

            new("l_jolt_get_position", "get_position",
                [new ParamBinding("id", new BindingType.Int())],
                Vec3Return, null,
                CustomCallCode: """
                        BodyID body_id((uint32){id});
                        RVec3 pos = {self}->physics_system->GetBodyInterface().GetPosition(body_id);
                        lua_pushnumber(L, pos.GetX());
                        lua_pushnumber(L, pos.GetY());
                        lua_pushnumber(L, pos.GetZ());
                    """,
                ReturnCount: 3),

            new("l_jolt_get_rotation", "get_rotation",
                [new ParamBinding("id", new BindingType.Int())],
                QuatReturn, null,
                CustomCallCode: """
                        BodyID body_id((uint32){id});
                        Quat rot = {self}->physics_system->GetBodyInterface().GetRotation(body_id);
                        lua_pushnumber(L, rot.GetX());
                        lua_pushnumber(L, rot.GetY());
                        lua_pushnumber(L, rot.GetZ());
                        lua_pushnumber(L, rot.GetW());
                    """,
                ReturnCount: 4),

            new("l_jolt_set_velocity", "set_linear_velocity",
                [new ParamBinding("id", new BindingType.Int()),
                 new ParamBinding("vx", new BindingType.Float()),
                 new ParamBinding("vy", new BindingType.Float()),
                 new ParamBinding("vz", new BindingType.Float())],
                new BindingType.Void(), null,
                CustomCallCode: "    {self}->physics_system->GetBodyInterface().SetLinearVelocity(BodyID((uint32){id}), Vec3({vx}, {vy}, {vz}));",
                ReturnCount: 0),

            new("l_jolt_add_impulse", "add_impulse",
                [new ParamBinding("id", new BindingType.Int()),
                 new ParamBinding("ix", new BindingType.Float()),
                 new ParamBinding("iy", new BindingType.Float()),
                 new ParamBinding("iz", new BindingType.Float())],
                new BindingType.Void(), null,
                CustomCallCode: "    {self}->physics_system->GetBodyInterface().AddImpulse(BodyID((uint32){id}), Vec3({ix}, {iy}, {iz}));",
                ReturnCount: 0),

            new("l_jolt_is_active", "is_active",
                [new ParamBinding("id", new BindingType.Int())],
                new BindingType.Void(), null,
                CustomCallCode: "    lua_pushboolean(L, {self}->physics_system->GetBodyInterface().IsActive(BodyID((uint32){id})));",
                ReturnCount: 1),

            new("l_jolt_body_count", "body_count",
                [], new BindingType.Void(), null,
                CustomCallCode: "    lua_pushinteger(L, (lua_Integer){self}->physics_system->GetNumActiveBodies(EBodyType::RigidBody));",
                ReturnCount: 1),

            // Micro-benchmark methods
            new("l_jolt_bench_noop", "bench_noop",
                [], new BindingType.Void(), null,
                CustomCallCode: "    (void){self};",
                ReturnCount: 0),

            new("l_jolt_bench_echo3", "bench_echo3",
                [new ParamBinding("x", new BindingType.Float()),
                 new ParamBinding("y", new BindingType.Float()),
                 new ParamBinding("z", new BindingType.Float())],
                new BindingType.Void(), null,
                CustomCallCode: """
                        (void){self};
                        lua_pushnumber(L, {x});
                        lua_pushnumber(L, {y});
                        lua_pushnumber(L, {z});
                    """,
                ReturnCount: 3),

            new("l_jolt_bench_echo16", "bench_echo16",
                [], new BindingType.Void(), null,
                CustomCallCode: """
                        (void){self};
                        float v[16];
                        for (int i = 0; i < 16; i++)
                            v[i] = (float)luaL_checknumber(L, i + 2);
                        for (int i = 0; i < 16; i++)
                            lua_pushnumber(L, v[i]);
                    """,
                ReturnCount: 16),

            new("l_jolt_bench_sum16", "bench_sum16",
                [], new BindingType.Void(), null,
                CustomCallCode: """
                        (void){self};
                        float sum = 0;
                        for (int i = 0; i < 16; i++)
                            sum += (float)luaL_checknumber(L, i + 2);
                        lua_pushnumber(L, sum);
                    """,
                ReturnCount: 1),
        };

        var opaqueTypes = new List<OpaqueTypeBinding>
        {
            new("JoltWorld", "World", "jolt.World", "jolt.World",
                null, null, null, null,
                worldMethods, null,
                CustomDestructorCode: "jolt_world_free(*{pp});\n        *{pp} = NULL;"),
        };

        // Module-level functions (for LuaCATS annotations)
        var extraLuaFuncs = new List<FuncBinding>
        {
            new("l_jolt_world_new", "init",
                [new ParamBinding("max_bodies", new BindingType.Int(), IsOptional: true),
                 new ParamBinding("max_body_pairs", new BindingType.Int(), IsOptional: true),
                 new ParamBinding("max_contact_constraints", new BindingType.Int(), IsOptional: true)],
                WorldType, null),
        };

        return new ModuleSpec(
            ModuleName, Prefix,
            CIncludes: [],
            ExtraCCode: JoltExtraCCode,
            Structs: [],
            Funcs: [],
            Enums: [],
            ExtraLuaRegs: [("init", "l_jolt_world_new")],
            OpaqueTypes: opaqueTypes,
            IsCpp: true,
            ExtraLuaFuncs: extraLuaFuncs,
            ExtraInitCode: """
                lua_pushinteger(L, 0); lua_setfield(L, -2, "STATIC");
                lua_pushinteger(L, 1); lua_setfield(L, -2, "KINEMATIC");
                lua_pushinteger(L, 2); lua_setfield(L, -2, "DYNAMIC");
            """);
    }

    public string GenerateC(TypeRegistry reg, Dictionary<string, string> prefixToModule)
    {
        var spec = BuildSpec(reg, prefixToModule);
        return CBinding.CBindingGen.Generate(spec);
    }

    public string GenerateLua(TypeRegistry reg, Dictionary<string, string> prefixToModule, SourceLink? sourceLink = null)
    {
        var spec = BuildSpec(reg, prefixToModule, sourceLink);
        var sb = LuaCats.LuaCatsGen.Header(spec.ModuleName);

        // World class with methods
        var ot = spec.OpaqueTypes[0];
        sb += $"---@class {ot.LuaClassName}\n";
        sb += $"---@field destroy fun(self: {ot.LuaClassName})\n";
        foreach (var m in ot.Methods)
        {
            var selfParam = $"self: {ot.LuaClassName}";
            var otherParams = string.Join(", ", m.Params.Select(p =>
            {
                var name = p.IsOptional ? p.Name + "?" : p.Name;
                var type = LuaCats.LuaCatsGen.ToLuaCatsType(p.Type);
                return $"{name}: {TypeToString(type)}";
            }));
            var allParams = string.IsNullOrEmpty(otherParams)
                ? selfParam : $"{selfParam}, {otherParams}";

            var ret = m.ReturnType is BindingType.Void ? "" : $": {TypeToString(LuaCats.LuaCatsGen.ToLuaCatsType(m.ReturnType))}";
            sb += $"---@field {m.LuaName} fun({allParams}){ret}\n";
        }
        sb += "\n";

        // Module class
        var moduleFields = new List<string>();

        // init function
        var initFunc = spec.ExtraLuaFuncs[0];
        var initParams = string.Join(", ", initFunc.Params.Select(p =>
        {
            var name = p.IsOptional ? p.Name + "?" : p.Name;
            var type = LuaCats.LuaCatsGen.ToLuaCatsType(p.Type);
            return $"{name}: {TypeToString(type)}";
        }));
        var initRet = TypeToString(LuaCats.LuaCatsGen.ToLuaCatsType(initFunc.ReturnType));
        moduleFields.Add($"---@field init fun({initParams}): {initRet}");

        // Motion type constants
        moduleFields.Add("---@field STATIC integer");
        moduleFields.Add("---@field KINEMATIC integer");
        moduleFields.Add("---@field DYNAMIC integer");

        sb += LuaCats.LuaCatsGen.ModuleClass(spec.ModuleName, moduleFields);
        sb += LuaCats.LuaCatsGen.Footer(spec.ModuleName);
        return sb;
    }

    SkipReport IModule.CollectSkips(TypeRegistry reg) => new(ModuleName, [], [], []);

    private static string TypeToString(LuaCats.Type typ) => typ switch
    {
        LuaCats.Type.Primitive(var name) => name,
        LuaCats.Type.Class(var fullName) => fullName,
        _ => "any"
    };
}
