# Tasks

## Pending

<!-- Template:
### Task name
- Background: why this task exists
- Requirements: what "done" looks like
- Approach: chosen design, affected components, key trade-offs
- Alternatives rejected: other options and why they were dropped
-->

<!-- T09, T01-T05 completed — see doc/done.md -->

<!-- ==================== Phase 2: Foundation research (blocks Phase 3 design quality) ==================== -->

### T06: Research ownership models (sol3, WASI) and improve Generator abstractions
- Background: The Generator currently handles ownership ad-hoc per module — opaque types (miniaudio), value structs (b2d), userdata with GC (sokol.app callbacks). There's no unified model for expressing who owns a resource, when it's freed, and how Lua GC interacts with C lifetimes. sol3 (C++/Lua binding library) and WASI (WebAssembly System Interface) both have well-defined ownership concepts that could inform better abstractions.
- Requirements: Study sol3's ownership model (unique_usertype, shared/value semantics, reference counting, move semantics in Lua bindings). Study WASI's resource model (own<T>/borrow<T> handle types, linear ownership, explicit drop). Identify patterns applicable to Generator's ModuleSpec. Propose concrete changes to Generator abstractions (e.g. BindingType, OpaqueType, struct ownership annotations). Write findings in done.md.
- Approach: Research phase first — read sol3 docs and source for usertype ownership, WASI component model spec for resource types. Then map current Generator patterns (OpaqueType init/uninit, HasMetamethods, value structs) to these models. Identify gaps (e.g. borrow semantics, preventing use-after-free). Propose ModuleSpec extensions without breaking existing modules.
- Alternatives rejected: Inventing our own model without reference — risks reinventing known solutions poorly.
- Goal: Written proposal with concrete ModuleSpec changes. At least one existing module (e.g. miniaudio OpaqueType) refactored as proof of concept.
- Stages:
  1. Read sol3 docs + source → summarize ownership patterns (value, reference, unique, shared)
  2. Read WASI component model spec → summarize own/borrow model
  3. Map current Generator patterns to these models → identify gaps
  4. Propose ModuleSpec changes → write up in done.md
  5. Proof of concept: refactor one module to use new abstractions

<!-- ==================== Phase 3: New bindings (benefits from T06 ownership model) ==================== -->

### T07: Add Jolt Physics binding
- Background: Box2D is 2D only. For 3D physics (sjadm, hakonotaiatari path tracer scenes, future 3D examples), a 3D physics engine is needed. Jolt Physics is a modern, high-performance 3D physics library (used in Horizon Forbidden West). The native API is C++.
- Requirements: Add a JoltModule to Generator that produces C++ bindings + LuaCATS annotations. Core API coverage: PhysicsSystem creation, body creation (static/dynamic/kinematic), shapes (box/sphere/capsule/convex hull/mesh), constraints, raycasting, collision queries. At least one working 3D physics example in examples/.
- Approach: Bind Jolt's C++ API directly, similar to how ImguiModule handles C++ (clang++ parsing with -std=c++17). Add deps/jolt submodule. Implement JoltModule as IModule with C++ namespace-based generation. Handle Jolt's RefCounted/Ref<T> ownership model (informed by T06). Start with rigid body basics, expand later.
- Alternatives rejected: JoltC (C wrapper) — adds an unnecessary indirection layer; the Generator already supports C++ binding via ImguiModule. Bullet Physics — older, less maintained. PhysX — heavy, complex build.
- Depends on: T06 (ownership model informs Ref<T> handling)
- Goal: Falling boxes demo running in examples/.
- Stages:
  1. Add deps/jolt submodule, verify CMake integration builds
  2. Implement JoltModule skeleton — clang++ parse Jolt headers, generate empty bindings
  3. Bind core: PhysicsSystem, BodyInterface, Body creation with basic shapes
  4. Bind queries: raycasting, collision detection
  5. Example: falling boxes with ground plane
  6. Bind constraints, expand shape types

### T08: Add ozz-animation binding
- Background: No skeletal animation support exists. ozz-animation is a lightweight, high-performance runtime animation library (C++) with offline tools for converting glTF/FBX to optimized runtime formats. Needed for character animation in 3D examples.
- Requirements: Add an OzzModule to Generator that produces C++ bindings + LuaCATS annotations. Core API coverage: skeleton loading, animation loading, sampling (SamplingJob), blending (BlendingJob), local-to-model transform (LocalToModelJob). At least one working skeletal animation example in examples/.
- Approach: Bind ozz's C++ API directly via clang++ parsing, same pattern as ImguiModule. Add deps/ozz-animation submodule. Key types: Skeleton, Animation, SamplingJob, BlendingJob, LocalToModelJob, SoaTransform. Handle ozz's span-based and SoA (Structure of Arrays) data layout — may need custom wrappers for Lua-friendly access.
- Alternatives rejected: Hand-written Lua animation system — reinventing the wheel. Spine — 2D only. Writing a C wrapper first — unnecessary given existing C++ binding support.
- Depends on: T06 (ownership model), T07 (shared learnings from C++ binding)
- Goal: Single character playing an idle animation in examples/.
- Stages:
  1. Add deps/ozz-animation submodule, verify CMake build
  2. Implement OzzModule skeleton — clang++ parse ozz headers
  3. Bind loading: Archive, Skeleton, Animation file I/O
  4. Bind runtime: SamplingJob, LocalToModelJob with Lua-friendly wrappers for SoA
  5. Bind blending: BlendingJob
  6. Example: character with idle animation

## Execution Order

```
Phase 0 + 1 (completed):       T09, T05, T02, T01, T03, T04
Phase 2 (next):                 T06
Phase 3 (after T06):            T07 → T08
```

Phase 2 can start immediately.
Phase 3 tasks are ordered: Jolt before ozz, since Jolt is simpler C++ binding (no SoA) and lessons learned carry over.

## Completed

See `doc/done.md`.
