/*
 * jolt_lua.cpp - Jolt Physics Lua bindings
 *
 * High-level wrapper: JoltWorld encapsulates PhysicsSystem + JobSystem +
 * TempAllocator + layer interfaces. Bodies are referenced by BodyID (integer).
 */

// Jolt includes (before Lua to avoid macro conflicts)
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

extern "C" {
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
}

// Jolt uses JPH namespace
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

// BroadPhaseLayer interface — maps ObjectLayer to BroadPhaseLayer
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

// ObjectLayer vs BroadPhaseLayer filter
class ObjectVsBroadPhaseLayerFilterImpl final : public ObjectVsBroadPhaseLayerFilter {
public:
    bool ShouldCollide(ObjectLayer inLayer1, BroadPhaseLayer inLayer2) const override {
        if (inLayer1 == Layers::NON_MOVING)
            return inLayer2 == BroadPhaseLayers::MOVING;
        return true;
    }
};

// ObjectLayer pair filter
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

static const char* JOLT_WORLD_MT = "jolt.World";

static JoltWorld* check_jolt_world(lua_State *L, int idx) {
    JoltWorld** pp = (JoltWorld**)luaL_checkudata(L, idx, JOLT_WORLD_MT);
    if (*pp == nullptr)
        luaL_error(L, "jolt.World has been destroyed");
    return *pp;
}

// ===== jolt.init() — create world =====

static bool s_jolt_registered = false;

static int l_jolt_world_new(lua_State *L) {
    // Register Jolt types (once per process)
    if (!s_jolt_registered) {
        RegisterDefaultAllocator();
        Factory::sInstance = new Factory();
        RegisterTypes();
        s_jolt_registered = true;
    }

    // Allocate world
    JoltWorld* world = new JoltWorld();
    world->temp_allocator = new TempAllocatorImpl(10 * 1024 * 1024); // 10 MB
    world->job_system = new JobSystemThreadPool(2048, 8, -1); // auto-detect threads
    world->bp_layer = new BPLayerInterfaceImpl();
    world->obj_vs_bp_filter = new ObjectVsBroadPhaseLayerFilterImpl();
    world->obj_pair_filter = new ObjectLayerPairFilterImpl();

    // Create physics system
    world->physics_system = new PhysicsSystem();
    uint max_bodies = (uint)luaL_optinteger(L, 1, 1024);
    uint num_body_mutexes = 0; // auto
    uint max_body_pairs = (uint)luaL_optinteger(L, 2, 1024);
    uint max_contact_constraints = (uint)luaL_optinteger(L, 3, 1024);
    world->physics_system->Init(
        max_bodies, num_body_mutexes, max_body_pairs, max_contact_constraints,
        *world->bp_layer, *world->obj_vs_bp_filter, *world->obj_pair_filter);

    // Create Lua userdata
    JoltWorld** pp = (JoltWorld**)lua_newuserdatauv(L, sizeof(JoltWorld*), 0);
    *pp = world;
    luaL_setmetatable(L, JOLT_WORLD_MT);
    return 1;
}

// ===== world:destroy() =====

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

static int l_jolt_world_gc(lua_State *L) {
    JoltWorld** pp = (JoltWorld**)luaL_checkudata(L, 1, JOLT_WORLD_MT);
    jolt_world_free(*pp);
    *pp = nullptr;
    return 0;
}

static int l_jolt_world_destroy(lua_State *L) {
    JoltWorld** pp = (JoltWorld**)luaL_checkudata(L, 1, JOLT_WORLD_MT);
    jolt_world_free(*pp);
    *pp = nullptr;
    return 0;
}

// ===== world:set_gravity(x, y, z) =====

static int l_jolt_set_gravity(lua_State *L) {
    JoltWorld* world = check_jolt_world(L, 1);
    float x = (float)luaL_checknumber(L, 2);
    float y = (float)luaL_checknumber(L, 3);
    float z = (float)luaL_checknumber(L, 4);
    world->physics_system->SetGravity(Vec3(x, y, z));
    return 0;
}

// ===== world:get_gravity() -> x, y, z =====

static int l_jolt_get_gravity(lua_State *L) {
    JoltWorld* world = check_jolt_world(L, 1);
    Vec3 g = world->physics_system->GetGravity();
    lua_pushnumber(L, g.GetX());
    lua_pushnumber(L, g.GetY());
    lua_pushnumber(L, g.GetZ());
    return 3;
}

// ===== world:update(dt, [collision_steps]) =====

static int l_jolt_update(lua_State *L) {
    JoltWorld* world = check_jolt_world(L, 1);
    float dt = (float)luaL_checknumber(L, 2);
    int steps = (int)luaL_optinteger(L, 3, 1);
    EPhysicsUpdateError err = world->physics_system->Update(
        dt, steps, world->temp_allocator, world->job_system);
    lua_pushinteger(L, (lua_Integer)err);
    return 1;
}

// ===== world:optimize() =====

static int l_jolt_optimize(lua_State *L) {
    JoltWorld* world = check_jolt_world(L, 1);
    world->physics_system->OptimizeBroadPhase();
    return 0;
}

// ===== world:create_box(hx, hy, hz, x, y, z, motion_type) -> body_id =====
// motion_type: 0=static, 1=kinematic, 2=dynamic

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

static int l_jolt_create_box(lua_State *L) {
    JoltWorld* world = check_jolt_world(L, 1);
    float hx = (float)luaL_checknumber(L, 2);
    float hy = (float)luaL_checknumber(L, 3);
    float hz = (float)luaL_checknumber(L, 4);
    float px = (float)luaL_checknumber(L, 5);
    float py = (float)luaL_checknumber(L, 6);
    float pz = (float)luaL_checknumber(L, 7);
    EMotionType mt = motion_type_from_int((int)luaL_optinteger(L, 8, 2));

    BoxShapeSettings shape_settings(Vec3(hx, hy, hz));
    ShapeSettings::ShapeResult shape_result = shape_settings.Create();
    if (shape_result.HasError())
        return luaL_error(L, "BoxShape creation failed: %s", shape_result.GetError().c_str());

    BodyCreationSettings body_settings(
        shape_result.Get(), RVec3(px, py, pz), Quat::sIdentity(), mt, layer_for_motion(mt));

    BodyInterface& bi = world->physics_system->GetBodyInterface();
    BodyID id = bi.CreateAndAddBody(body_settings, mt == EMotionType::Static ? EActivation::DontActivate : EActivation::Activate);

    if (id.IsInvalid())
        return luaL_error(L, "CreateAndAddBody failed");

    lua_pushinteger(L, (lua_Integer)id.GetIndexAndSequenceNumber());
    return 1;
}

// ===== world:create_sphere(radius, x, y, z, motion_type) -> body_id =====

static int l_jolt_create_sphere(lua_State *L) {
    JoltWorld* world = check_jolt_world(L, 1);
    float radius = (float)luaL_checknumber(L, 2);
    float px = (float)luaL_checknumber(L, 3);
    float py = (float)luaL_checknumber(L, 4);
    float pz = (float)luaL_checknumber(L, 5);
    EMotionType mt = motion_type_from_int((int)luaL_optinteger(L, 6, 2));

    SphereShapeSettings shape_settings(radius);
    ShapeSettings::ShapeResult shape_result = shape_settings.Create();
    if (shape_result.HasError())
        return luaL_error(L, "SphereShape creation failed: %s", shape_result.GetError().c_str());

    BodyCreationSettings body_settings(
        shape_result.Get(), RVec3(px, py, pz), Quat::sIdentity(), mt, layer_for_motion(mt));

    BodyInterface& bi = world->physics_system->GetBodyInterface();
    BodyID id = bi.CreateAndAddBody(body_settings, mt == EMotionType::Static ? EActivation::DontActivate : EActivation::Activate);

    if (id.IsInvalid())
        return luaL_error(L, "CreateAndAddBody failed");

    lua_pushinteger(L, (lua_Integer)id.GetIndexAndSequenceNumber());
    return 1;
}

// ===== world:remove_body(id) =====

static int l_jolt_remove_body(lua_State *L) {
    JoltWorld* world = check_jolt_world(L, 1);
    BodyID id((uint32)luaL_checkinteger(L, 2));
    BodyInterface& bi = world->physics_system->GetBodyInterface();
    bi.RemoveBody(id);
    bi.DestroyBody(id);
    return 0;
}

// ===== world:get_position(id) -> x, y, z =====

static int l_jolt_get_position(lua_State *L) {
    JoltWorld* world = check_jolt_world(L, 1);
    BodyID id((uint32)luaL_checkinteger(L, 2));
    RVec3 pos = world->physics_system->GetBodyInterface().GetPosition(id);
    lua_pushnumber(L, pos.GetX());
    lua_pushnumber(L, pos.GetY());
    lua_pushnumber(L, pos.GetZ());
    return 3;
}

// ===== world:get_rotation(id) -> x, y, z, w =====

static int l_jolt_get_rotation(lua_State *L) {
    JoltWorld* world = check_jolt_world(L, 1);
    BodyID id((uint32)luaL_checkinteger(L, 2));
    Quat rot = world->physics_system->GetBodyInterface().GetRotation(id);
    lua_pushnumber(L, rot.GetX());
    lua_pushnumber(L, rot.GetY());
    lua_pushnumber(L, rot.GetZ());
    lua_pushnumber(L, rot.GetW());
    return 4;
}

// ===== world:set_linear_velocity(id, vx, vy, vz) =====

static int l_jolt_set_velocity(lua_State *L) {
    JoltWorld* world = check_jolt_world(L, 1);
    BodyID id((uint32)luaL_checkinteger(L, 2));
    float vx = (float)luaL_checknumber(L, 3);
    float vy = (float)luaL_checknumber(L, 4);
    float vz = (float)luaL_checknumber(L, 5);
    world->physics_system->GetBodyInterface().SetLinearVelocity(id, Vec3(vx, vy, vz));
    return 0;
}

// ===== world:add_impulse(id, ix, iy, iz) =====

static int l_jolt_add_impulse(lua_State *L) {
    JoltWorld* world = check_jolt_world(L, 1);
    BodyID id((uint32)luaL_checkinteger(L, 2));
    float ix = (float)luaL_checknumber(L, 3);
    float iy = (float)luaL_checknumber(L, 4);
    float iz = (float)luaL_checknumber(L, 5);
    world->physics_system->GetBodyInterface().AddImpulse(id, Vec3(ix, iy, iz));
    return 0;
}

// ===== world:is_active(id) -> bool =====

static int l_jolt_is_active(lua_State *L) {
    JoltWorld* world = check_jolt_world(L, 1);
    BodyID id((uint32)luaL_checkinteger(L, 2));
    lua_pushboolean(L, world->physics_system->GetBodyInterface().IsActive(id));
    return 1;
}

// ===== world:body_count() -> int =====

static int l_jolt_body_count(lua_State *L) {
    JoltWorld* world = check_jolt_world(L, 1);
    lua_pushinteger(L, (lua_Integer)world->physics_system->GetNumActiveBodies(EBodyType::RigidBody));
    return 1;
}

// ===== Module registration =====

static const luaL_Reg jolt_world_methods[] = {
    {"destroy",             l_jolt_world_destroy},
    {"set_gravity",         l_jolt_set_gravity},
    {"get_gravity",         l_jolt_get_gravity},
    {"update",              l_jolt_update},
    {"optimize",            l_jolt_optimize},
    {"create_box",          l_jolt_create_box},
    {"create_sphere",       l_jolt_create_sphere},
    {"remove_body",         l_jolt_remove_body},
    {"get_position",        l_jolt_get_position},
    {"get_rotation",        l_jolt_get_rotation},
    {"set_linear_velocity", l_jolt_set_velocity},
    {"add_impulse",         l_jolt_add_impulse},
    {"is_active",           l_jolt_is_active},
    {"body_count",          l_jolt_body_count},
    {NULL, NULL}
};

static const luaL_Reg jolt_funcs[] = {
    {"init", l_jolt_world_new},
    {NULL, NULL}
};

extern "C" int luaopen_jolt(lua_State *L) {
    // Create World metatable
    luaL_newmetatable(L, JOLT_WORLD_MT);
    lua_pushcfunction(L, l_jolt_world_gc);
    lua_setfield(L, -2, "__gc");
    luaL_newlib(L, jolt_world_methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);

    // Module table
    luaL_newlib(L, jolt_funcs);

    // Motion type constants
    lua_pushinteger(L, 0); lua_setfield(L, -2, "STATIC");
    lua_pushinteger(L, 1); lua_setfield(L, -2, "KINEMATIC");
    lua_pushinteger(L, 2); lua_setfield(L, -2, "DYNAMIC");

    return 1;
}
