// Jolt Physics extra code — JoltWorld wrapper struct and helpers
// This is included in the generated jolt binding via ExtraCCode.

#include <Jolt/Jolt.h>
#include <Jolt/RegisterTypes.h>
#include <Jolt/Core/Factory.h>
#include <Jolt/Core/TempAllocator.h>
#include <Jolt/Core/JobSystemThreadPool.h>
#include <Jolt/Physics/PhysicsSettings.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/Collision/Shape/SphereShape.h>

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
        if (inLayer1 == Layers::NON_MOVING) return inLayer2 == BroadPhaseLayers::MOVING;
        return true;
    }
};

class ObjectLayerPairFilterImpl final : public ObjectLayerPairFilter {
public:
    bool ShouldCollide(ObjectLayer inLayer1, ObjectLayer inLayer2) const override {
        if (inLayer1 == Layers::NON_MOVING && inLayer2 == Layers::NON_MOVING) return false;
        return true;
    }
};

// ===== JoltWorld — wraps PhysicsSystem + subsystems =====

static bool s_jolt_registered = false;

struct JoltWorld {
    PhysicsSystem*                      physics_system;
    TempAllocatorImpl*                  temp_allocator;
    JobSystemThreadPool*                job_system;
    BPLayerInterfaceImpl*               bp_layer;
    ObjectVsBroadPhaseLayerFilterImpl*  obj_vs_bp_filter;
    ObjectLayerPairFilterImpl*          obj_pair_filter;

    JoltWorld(unsigned int max_bodies, unsigned int max_body_pairs,
              unsigned int max_contact_constraints) {
        if (!s_jolt_registered) {
            RegisterDefaultAllocator();
            Factory::sInstance = new Factory();
            RegisterTypes();
            s_jolt_registered = true;
        }
        temp_allocator = new TempAllocatorImpl(10 * 1024 * 1024);
        job_system = new JobSystemThreadPool(2048, 8, -1);
        bp_layer = new BPLayerInterfaceImpl();
        obj_vs_bp_filter = new ObjectVsBroadPhaseLayerFilterImpl();
        obj_pair_filter = new ObjectLayerPairFilterImpl();
        physics_system = new PhysicsSystem();
        physics_system->Init(max_bodies, 0, max_body_pairs, max_contact_constraints,
            *bp_layer, *obj_vs_bp_filter, *obj_pair_filter);
    }

    ~JoltWorld() {
        delete physics_system;
        delete job_system;
        delete temp_allocator;
        delete bp_layer;
        delete obj_vs_bp_filter;
        delete obj_pair_filter;
    }

    // --- IDL-bound methods (simple dispatch) ---

    void set_gravity(float x, float y, float z) {
        physics_system->SetGravity(Vec3(x, y, z));
    }

    int update(float dt, int steps) {
        return (int)physics_system->Update(dt, steps, temp_allocator, job_system);
    }

    void optimize() {
        physics_system->OptimizeBroadPhase();
    }

    unsigned int body_count() {
        return (unsigned int)physics_system->GetNumActiveBodies(EBodyType::RigidBody);
    }

    bool is_active(unsigned int body_id) {
        return physics_system->GetBodyInterface().IsActive(BodyID(body_id));
    }

    void remove_body(unsigned int body_id) {
        BodyInterface& bi = physics_system->GetBodyInterface();
        BodyID id(body_id);
        bi.RemoveBody(id);
        bi.DestroyBody(id);
    }

    void set_linear_velocity(unsigned int body_id, float vx, float vy, float vz) {
        physics_system->GetBodyInterface().SetLinearVelocity(BodyID(body_id), Vec3(vx, vy, vz));
    }

    void add_impulse(unsigned int body_id, float ix, float iy, float iz) {
        physics_system->GetBodyInterface().AddImpulse(BodyID(body_id), Vec3(ix, iy, iz));
    }

    unsigned int create_box(float hx, float hy, float hz,
                            float px, float py, float pz, int motion_type) {
        EMotionType mt = (EMotionType)motion_type;
        ObjectLayer layer = mt == EMotionType::Static ? Layers::NON_MOVING : Layers::MOVING;
        BoxShapeSettings shape_settings(Vec3(hx, hy, hz));
        ShapeSettings::ShapeResult shape_result = shape_settings.Create();
        BodyCreationSettings body_settings(
            shape_result.Get(), RVec3(px, py, pz), Quat::sIdentity(), mt, layer);
        BodyInterface& bi = physics_system->GetBodyInterface();
        BodyID id = bi.CreateAndAddBody(body_settings,
            mt == EMotionType::Static ? EActivation::DontActivate : EActivation::Activate);
        return id.GetIndexAndSequenceNumber();
    }

    unsigned int create_sphere(float radius, float px, float py, float pz, int motion_type) {
        EMotionType mt = (EMotionType)motion_type;
        ObjectLayer layer = mt == EMotionType::Static ? Layers::NON_MOVING : Layers::MOVING;
        SphereShapeSettings shape_settings(radius);
        ShapeSettings::ShapeResult shape_result = shape_settings.Create();
        BodyCreationSettings body_settings(
            shape_result.Get(), RVec3(px, py, pz), Quat::sIdentity(), mt, layer);
        BodyInterface& bi = physics_system->GetBodyInterface();
        BodyID id = bi.CreateAndAddBody(body_settings,
            mt == EMotionType::Static ? EActivation::DontActivate : EActivation::Activate);
        return id.GetIndexAndSequenceNumber();
    }
};

// --- Custom constructor with optional params ---

static int l_jolt_World_new(lua_State *L) {
    unsigned int max_bodies = (unsigned int)luaL_optinteger(L, 1, 1024);
    unsigned int max_body_pairs = (unsigned int)luaL_optinteger(L, 2, 1024);
    unsigned int max_contact_constraints = (unsigned int)luaL_optinteger(L, 3, 1024);
    JoltWorld* p = new JoltWorld(max_bodies, max_body_pairs, max_contact_constraints);
    JoltWorld** pp = (JoltWorld**)lua_newuserdatauv(L, sizeof(JoltWorld*), 0);
    *pp = p;
    luaL_setmetatable(L, "jolt.World");
    return 1;
}

// --- Custom Lua functions for multi-return values ---

// Forward declaration of check helper (generated by pipeline)
static JoltWorld* check_World(lua_State *L, int idx);

static int l_jolt_get_gravity(lua_State *L) {
    JoltWorld* self = check_World(L, 1);
    Vec3 g = self->physics_system->GetGravity();
    lua_pushnumber(L, g.GetX());
    lua_pushnumber(L, g.GetY());
    lua_pushnumber(L, g.GetZ());
    return 3;
}

static int l_jolt_get_position(lua_State *L) {
    JoltWorld* self = check_World(L, 1);
    BodyID id((uint32)luaL_checkinteger(L, 2));
    RVec3 pos = self->physics_system->GetBodyInterface().GetPosition(id);
    lua_pushnumber(L, pos.GetX());
    lua_pushnumber(L, pos.GetY());
    lua_pushnumber(L, pos.GetZ());
    return 3;
}

static int l_jolt_get_rotation(lua_State *L) {
    JoltWorld* self = check_World(L, 1);
    BodyID id((uint32)luaL_checkinteger(L, 2));
    Quat rot = self->physics_system->GetBodyInterface().GetRotation(id);
    lua_pushnumber(L, rot.GetX());
    lua_pushnumber(L, rot.GetY());
    lua_pushnumber(L, rot.GetZ());
    lua_pushnumber(L, rot.GetW());
    return 4;
}
