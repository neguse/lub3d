// Jolt Physics extra code — JoltWorld wrapper struct and helpers
// This is included in the generated jolt binding via ExtraCCode.

#include <Jolt/Jolt.h>
#include <Jolt/RegisterTypes.h>
#include <Jolt/Core/Factory.h>
#include <Jolt/Core/TempAllocator.h>
#include <Jolt/Core/JobSystemThreadPool.h>
#include <Jolt/Math/Float2.h>
#include <Jolt/Math/Vec4.h>
#include <Jolt/Geometry/Plane.h>
#include <Jolt/Geometry/AABox.h>
#include <Jolt/Geometry/OrientedBox.h>
#include <Jolt/Geometry/Triangle.h>
#include <Jolt/Geometry/IndexedTriangle.h>
#include <Jolt/Physics/PhysicsSettings.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Body/BodyInterface.h>
#include <Jolt/Physics/Collision/TransformedShape.h>
#include <Jolt/Physics/Collision/CollideShape.h>
#include <Jolt/Physics/Collision/ShapeCast.h>
#include <Jolt/Physics/Collision/ShapeFilter.h>
#include <Jolt/Physics/Collision/SimShapeFilter.h>
#include <Jolt/Physics/Collision/CollisionCollectorImpl.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/Collision/Shape/SphereShape.h>
#include <Jolt/Physics/Collision/Shape/CapsuleShape.h>
#include <Jolt/Physics/Collision/Shape/CylinderShape.h>
#include <Jolt/Physics/Collision/Shape/TaperedCapsuleShape.h>
#include <Jolt/Physics/Collision/Shape/TaperedCylinderShape.h>
#include <Jolt/Physics/Collision/Shape/ConvexHullShape.h>
#include <Jolt/Physics/Collision/Shape/CompoundShape.h>
#include <Jolt/Physics/Collision/Shape/StaticCompoundShape.h>
#include <Jolt/Physics/Collision/Shape/MutableCompoundShape.h>
#include <Jolt/Physics/Collision/Shape/DecoratedShape.h>
#include <Jolt/Physics/Collision/Shape/ScaledShape.h>
#include <Jolt/Physics/Collision/Shape/OffsetCenterOfMassShape.h>
#include <Jolt/Physics/Collision/Shape/RotatedTranslatedShape.h>
#include <Jolt/Physics/Collision/Shape/MeshShape.h>
#include <Jolt/Physics/Collision/Shape/HeightFieldShape.h>
#include <Jolt/Physics/Collision/Shape/PlaneShape.h>
#include <Jolt/Physics/Collision/Shape/EmptyShape.h>
#include <Jolt/Physics/Collision/Shape/SubShapeID.h>
#include <Jolt/Physics/Collision/Shape/SubShapeIDPair.h>
#include <Jolt/Physics/Collision/Shape/GetTrianglesContext.h>
#include <Jolt/Physics/SoftBody/SoftBodyShape.h>
#include <Jolt/Physics/SoftBody/SoftBodyContactListener.h>
#include <Jolt/Physics/Collision/RayCast.h>
#include <Jolt/Physics/Collision/CastResult.h>
#include <Jolt/Physics/Collision/CollidePointResult.h>
#include <Jolt/Physics/Collision/NarrowPhaseQuery.h>
#include <Jolt/Physics/Collision/CollisionGroup.h>
#include <Jolt/Physics/Collision/GroupFilter.h>
#include <Jolt/Physics/Collision/GroupFilterTable.h>
#include <Jolt/Physics/Collision/ContactListener.h>
#include <Jolt/Physics/Collision/ObjectLayerPairFilterTable.h>
#include <Jolt/Physics/Collision/ObjectLayerPairFilterMask.h>
#include <Jolt/Physics/Collision/AABoxCast.h>
#include <Jolt/Physics/Collision/BroadPhase/BroadPhaseQuery.h>
#include <Jolt/Physics/Collision/BroadPhase/BroadPhaseLayer.h>
#include <Jolt/Physics/Collision/BroadPhase/BroadPhaseLayerInterfaceTable.h>
#include <Jolt/Physics/Collision/BroadPhase/BroadPhaseLayerInterfaceMask.h>
#include <Jolt/Physics/Collision/BroadPhase/ObjectVsBroadPhaseLayerFilterTable.h>
#include <Jolt/Physics/Collision/BroadPhase/ObjectVsBroadPhaseLayerFilterMask.h>
#include <Jolt/Physics/Body/BodyFilter.h>
#include <Jolt/Physics/Body/BodyActivationListener.h>
#include <Jolt/Physics/Character/CharacterVirtual.h>
#include <Jolt/Physics/Vehicle/VehicleCollisionTester.h>
#include <Jolt/Physics/StateRecorder.h>
#include <Jolt/Physics/StateRecorderImpl.h>
#include <Jolt/Physics/Constraints/Constraint.h>
#include <Jolt/Physics/Constraints/TwoBodyConstraint.h>
#include <Jolt/Physics/Constraints/FixedConstraint.h>
#include <Jolt/Physics/Constraints/DistanceConstraint.h>
#include <Jolt/Physics/Constraints/PointConstraint.h>
#include <Jolt/Physics/Constraints/HingeConstraint.h>
#include <Jolt/Physics/Constraints/ConeConstraint.h>
#include <Jolt/Physics/Constraints/SliderConstraint.h>
#include <Jolt/Physics/Constraints/SwingTwistConstraint.h>
#include <Jolt/Physics/Constraints/SixDOFConstraint.h>
#include <Jolt/Physics/Constraints/PathConstraint.h>
#include <Jolt/Physics/Constraints/PathConstraintPath.h>
#include <Jolt/Physics/Constraints/PathConstraintPathHermite.h>
#include <Jolt/Physics/Constraints/PulleyConstraint.h>
#include <Jolt/Physics/Constraints/GearConstraint.h>
#include <Jolt/Physics/Constraints/RackAndPinionConstraint.h>
#include <Jolt/Physics/Constraints/SpringSettings.h>
#include <Jolt/Physics/Constraints/MotorSettings.h>
#include <Jolt/Physics/Vehicle/VehicleConstraint.h>
#include <Jolt/Physics/Vehicle/VehicleController.h>
#include <Jolt/Physics/Vehicle/VehicleEngine.h>
#include <Jolt/Physics/Vehicle/VehicleTransmission.h>
#include <Jolt/Physics/Vehicle/VehicleDifferential.h>
#include <Jolt/Physics/Vehicle/VehicleTrack.h>
#include <Jolt/Physics/Vehicle/VehicleAntiRollBar.h>
#include <Jolt/Physics/Vehicle/Wheel.h>
#include <Jolt/Physics/Vehicle/WheeledVehicleController.h>
#include <Jolt/Physics/Vehicle/TrackedVehicleController.h>
#include <Jolt/Physics/Vehicle/MotorcycleController.h>
#include <Jolt/Physics/SoftBody/SoftBodyCreationSettings.h>
#include <Jolt/Physics/SoftBody/SoftBodySharedSettings.h>
#include <Jolt/Physics/SoftBody/SoftBodyVertex.h>
#include <Jolt/Physics/SoftBody/SoftBodyManifold.h>
#include <Jolt/Physics/SoftBody/SoftBodyMotionProperties.h>
#include <Jolt/Physics/Ragdoll/Ragdoll.h>
#include <Jolt/Skeleton/Skeleton.h>
#include <Jolt/Skeleton/SkeletonPose.h>
#include <Jolt/Skeleton/SkeletalAnimation.h>
#include <Jolt/Physics/Body/BodyLockInterface.h>
#include <Jolt/Physics/PhysicsStepListener.h>
#include <Jolt/Core/LinearCurve.h>

// Template aliases for collector types
using CollideShapeAllHitCollisionCollector = JPH::AllHitCollisionCollector<JPH::CollideShapeCollector>;
using CollideShapeClosestHitCollisionCollector = JPH::ClosestHitCollisionCollector<JPH::CollideShapeCollector>;
using CollideShapeAnyHitCollisionCollector = JPH::AnyHitCollisionCollector<JPH::CollideShapeCollector>;
using CastShapeAllHitCollisionCollector = JPH::AllHitCollisionCollector<JPH::CastShapeCollector>;
using CastShapeClosestHitCollisionCollector = JPH::ClosestHitCollisionCollector<JPH::CastShapeCollector>;
using CastShapeAnyHitCollisionCollector = JPH::AnyHitCollisionCollector<JPH::CastShapeCollector>;

// CastRay collector aliases
using CastRayAllHitCollisionCollector = JPH::AllHitCollisionCollector<JPH::CastRayCollector>;
using CastRayClosestHitCollisionCollector = JPH::ClosestHitCollisionCollector<JPH::CastRayCollector>;
using CastRayAnyHitCollisionCollector = JPH::AnyHitCollisionCollector<JPH::CastRayCollector>;

// CollidePoint collector aliases
using CollidePointAllHitCollisionCollector = JPH::AllHitCollisionCollector<JPH::CollidePointCollector>;
using CollidePointClosestHitCollisionCollector = JPH::ClosestHitCollisionCollector<JPH::CollidePointCollector>;
using CollidePointAnyHitCollisionCollector = JPH::AnyHitCollisionCollector<JPH::CollidePointCollector>;

// Nested enum/type aliases
using SixDOFConstraintSettings_EAxis = JPH::SixDOFConstraintSettings::EAxis;
using MeshShapeSettings_EBuildQuality = JPH::MeshShapeSettings::EBuildQuality;
using SoftBodySharedSettings_EBendType = JPH::SoftBodySharedSettings::EBendType;
using SoftBodySharedSettings_ELRAType = JPH::SoftBodySharedSettings::ELRAType;
using SoftBodySharedSettingsVertex = JPH::SoftBodySharedSettings::Vertex;
using SoftBodySharedSettingsEdge = JPH::SoftBodySharedSettings::Edge;
using SoftBodySharedSettingsFace = JPH::SoftBodySharedSettings::Face;
using SoftBodySharedSettingsVolume = JPH::SoftBodySharedSettings::Volume;
using SoftBodySharedSettingsDihedralBend = JPH::SoftBodySharedSettings::DihedralBend;
using SoftBodySharedSettingsLRA = JPH::SoftBodySharedSettings::LRA;
using SoftBodySharedSettingsVertexAttributes = JPH::SoftBodySharedSettings::VertexAttributes;
using RagdollPart = JPH::RagdollSettings::Part;
using SkeletalAnimationKeyframe = JPH::SkeletalAnimation::Keyframe;
using SkeletalAnimationJointState = JPH::SkeletalAnimation::JointState;
using SoftBodySharedSettingsRodStretchShear = JPH::SoftBodySharedSettings::RodStretchShear;
using SoftBodySharedSettingsRodBendTwist = JPH::SoftBodySharedSettings::RodBendTwist;
using SkeletalAnimationAnimatedJoint = JPH::SkeletalAnimation::AnimatedJoint;

// Wrapper: PhysicsStepListenerContext — expose read-only members as methods
struct PhysicsStepListenerContextWrapper {
    float mDeltaTime;
    bool mIsFirstStep;
    bool mIsLastStep;

    float GetDeltaTime() { return mDeltaTime; }
    bool GetIsFirstStep() { return mIsFirstStep; }
    bool GetIsLastStep() { return mIsLastStep; }
};

// Wrapper: HeightFieldShapeConstantValues
struct HeightFieldShapeConstantValues {
    HeightFieldShapeConstantValues() = default;
    float GetNoCollisionValue() { return JPH::HeightFieldShapeConstants::cNoCollisionValue; }
};

// Wrapper: ShapeGetTriangles — collects all triangles from a shape
struct ShapeGetTrianglesWrapper {
    std::vector<JPH::Float3> mVertices;
    int mNumTriangles = 0;

    ShapeGetTrianglesWrapper(const JPH::Shape* inShape, const JPH::AABox& inBox,
                             JPH::Vec3Arg inPositionCOM, JPH::QuatArg inRotation, JPH::Vec3Arg inScale) {
        JPH::Shape::GetTrianglesContext ctx;
        inShape->GetTrianglesStart(ctx, inBox, inPositionCOM, inRotation, inScale);
        for (;;) {
            constexpr int cBatchSize = 1024;
            size_t offset = mVertices.size();
            mVertices.resize(offset + cBatchSize * 3);
            int count = inShape->GetTrianglesNext(ctx, cBatchSize, &mVertices[offset], nullptr);
            if (count == 0) {
                mVertices.resize(offset);
                break;
            }
            mNumTriangles += count;
            mVertices.resize(offset + count * 3);
        }
    }

    ~ShapeGetTrianglesWrapper() = default;

    int GetNumTriangles() { return mNumTriangles; }
    int GetVerticesSize() { return (int)mVertices.size(); }
};

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

// ===== JoltSettings — simple config struct for JoltInterface =====

struct JoltSettings {
    unsigned int mMaxBodies = 10240;
    unsigned int mMaxBodyPairs = 65536;
    unsigned int mMaxContactConstraints = 10240;
    unsigned int mMaxWorkerThreads = 4;

    JoltSettings() = default;

    unsigned int get_max_bodies() { return mMaxBodies; }
    void set_max_bodies(unsigned int v) { mMaxBodies = v; }
    unsigned int get_max_body_pairs() { return mMaxBodyPairs; }
    void set_max_body_pairs(unsigned int v) { mMaxBodyPairs = v; }
    unsigned int get_max_contact_constraints() { return mMaxContactConstraints; }
    void set_max_contact_constraints(unsigned int v) { mMaxContactConstraints = v; }
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
