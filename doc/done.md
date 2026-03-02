# Completed Tasks

<!-- Add newest entries at the top -->

### Phase 5: Box2D WebIDL Migration ✓ (2026-03-02)
- Migrated Box2D module (~1050-line Box2dModule.cs) to WebIDL-based pipeline
- Extended WebIDL IR: IdlCallback, IdlEventAdapter, IdlField.ExtAttrs, IdlFile Callbacks/EventAdapters
- Extended WebIDL parser: `callback`, `event` keywords, per-field ExtAttr, dictionary FixedArray syntax (`type name[N]`)
- Extended WebIdlToSpec converter: ValueStruct, HandleType, Callback (Immediate/Persistent), FuncNaming="PascalCase", EnumItemStyle="CamelCase", ArrayAdapter, EventAdapter, OutputParams, PostCallPatch, PropertyBinding file loading, multiple CInclude, PromoteStructParam (HandleType-aware)
- Created idl/box2d.idl (~1040 lines): 6 ValueStruct, 5 Callback, 5 HandleType, 4 Enum, ~30 Struct, ~380 namespace functions, 4 ArrayAdapter, 3 EventAdapter
- Created idl/extra/box2d_extra.c (~170 lines), b2_chain_points.c, b2_chain_materials.c (PropertyBinding)
- Fixed CBindingGen: VoidPtr support in BindingTypeToString
- Fixed Program.cs: idlBasePath passthrough, SpecTransform.ExpandHandleTypes for IDL pipeline
- E2E verification: function name list exact match (unique), 42 metatables match, C 8584 lines / Lua 785 lines
- Files: WebIdlIr.cs, WebIdlParser.cs, WebIdlToSpec.cs, CBindingGen.cs, Program.cs, WebIdlBox2dTests.cs (23 tests), idl/box2d.idl, idl/extra/box2d_extra.c, idl/extra/b2_chain_points.c, idl/extra/b2_chain_materials.c
- Tests: 570 Generator.Tests pass (547 existing + 23 new)
- What went well: ExtAttr-based approach kept new keywords to minimum (callback, event only). PromoteStructParam with HandleType awareness cleanly separates value-pass vs pointer-pass semantics
- Decisions: b2Manifold not exposed (SkipStruct) — collide functions return void, manifold accessed via ExtraCCode functions. CFunc explicit naming on EventAdapter to avoid PascalCase underscore removal. PropertyBinding type specified in ExtAttr value ("path:type" format)
- Remaining: Box2dModule.cs still used for production generation — IDL pipeline is verified-equivalent but not yet the primary path

### T07: Add Jolt Physics binding ✓ (2026-02-23)
- Added Jolt Physics v5.5.0 Lua binding with JoltWorld opaque type wrapping PhysicsSystem + JobSystem + TempAllocator
- 15 Lua API functions: init, destroy, set_gravity, get_gravity, update, optimize, create_box, create_sphere, remove_body, get_position, get_rotation, set_linear_velocity, add_impulse, is_active, body_count
- CMake integration: `LUB3D_BUILD_JOLT` option, `add_subdirectory(deps/JoltPhysics/Build)`, separate jolt_lua static library, static MSVC CRT (`/MT`) for all targets
- Generator: JoltModule.cs (IModule, LuaCATS-only — no clang parsing), 15 xUnit tests
- Demo: `examples/jolt_hello.lua` — 3D wireframe falling boxes with sokol.gl, orbit camera, spawn on click/key
- Playground: `jolt_hello` をサンプルセレクトに追加
- `check.py`: モジュールレベル UPPER_CASE 定数の命名規則許可を追加
- Files: CMakeLists.txt, src/jolt_lua.cpp, src/lub3d_lua.c, Generator/Modules/Jolt/JoltModule.cs, Generator/Program.cs, Generator.Tests/JoltModuleTests.cs, gen/jolt.lua, examples/jolt_hello.lua, playground/main.ts, scripts/check.py
- What went well: Hand-written C++ binding + Generator LuaCATS annotation hybrid approach — pragmatic and fast
- Decisions: BodyID as Lua integer (lightweight handle), fixed 2-layer broadphase (NON_MOVING/MOVING), no clang++ auto-generation (Jolt is class-based C++, current ClangAst handles namespace-level only), static CRT for game distribution
- Remaining: 拡張バインディング (constraints, raycasting, shapes, body properties)

### T06-impl: Implement Generator ownership abstractions ✓ (2026-02-23)
- Added `DependencyBinding` record to `ModuleSpec.cs` for parent-child lifetime tracking via Lua uservalue slots (sol3 `self_dependency` pattern)
- Auto-generate `destroy()` method for all opaque types with `UninitFunc` — deterministic cleanup alongside GC
- Wired `ma_sound → ma_engine` dependency in miniaudio `ExtraCCode` as PoC (uservalue slot 1)
- Removed `doc/current.md` — redundant with PR-based workflow
- Files: `ModuleSpec.cs`, `CBindingGen.cs`, `LuaCatsGen.cs`, `MiniaudioModule.cs`, `OpaqueTypeGenTests.cs`, `MiniaudioModuleTests.cs`, `CLAUDE.md`
- Tests: 482 Generator.Tests pass (477 existing + 5 new)
- What went well: nullable-with-default pattern (`List<DependencyBinding>? Dependencies = null`) kept all existing call sites untouched
- Decisions: destroy method always generated when UninitFunc exists (no flag needed). ExtraCCode hand-written constructors need manual uservalue wiring separate from generated ones
- Remaining: none for core feature. ParamOwnership deferred to T07/T08

### T10: Fix lubs check warnings (60 items) ✓ (2026-02-23)
- Fixed 60 warnings from lubs check: removed unused requires (9), renamed unused params with `_` prefix (26), removed/cleaned unused variables (14), removed dead GC anchor declarations in sprite.lua (2), renamed shadowed variable in rendering/init.lua (1), suppressed global_usage in headless_app.lua (1)
- lua-language-server `name-style-check` rejected `_` prefix as non-snake-case; fixed by adding `^_[a-z][a-z0-9_]*$` pattern to `function_param_name_style` and `local_name_style` in `.luarc.json`
- Fixed `@param` annotation mismatches (lighting.lua ctx→_ctx, playfield.lua current_beat→_current_beat)
- Removed invalid `global_usage` diagnostic suppress — it's a lubs-only code; lua-language-server uses `diagnostics.globals` instead
- Files: 28 Lua files, `.luarc.json`
- Tests: CI lua-lint + headless-test pass
- What went well: discovered lubs vs lua-language-server diagnostic code differences — useful for future lint work
- Decisions: allowed `_` prefix via `.luarc.json` pattern rather than reverting to original names. 3 lubs-side type precision issues left unfixed (not our problem)
- Remaining: none

### T06: Research ownership models (sol3, WASI) ✓ (2026-02-23)
- Researched sol3 ownership model (value/reference/smart pointer semantics) and WASI Component Model resource model (own/borrow handles)
- Mapped current Generator patterns (ValueStruct/OpaqueType/HandleType) to sol3/WASI equivalents
- Gap analysis: dependency lifetime tracking (high priority), explicit destroy (medium), parameter ownership (low)
- Designed Generator improvements: `DependencyBinding` (sol3 self_dependency approach), destroy auto-generation (WASI resource.drop approach)
- Files: `doc/ownership-research.md`, `doc/ownership-design.md`
- Tests: none (research/documentation task)
- What went well: sol3's uservalue reference pattern maps directly to Lua 5.5 `lua_setiuservalue`
- Decisions: rejected WASI `num_lends` counter as overkill for single-threaded Lua; adopted sol3 uservalue approach. ParamOwnership deferred to T07/T08
- Remaining: implementation phase (tracked as T06-impl)

### T09 + T01-T05: Skip-aware metrics + full module audit ✓ (2026-02-23)
- Added `SkipEntry`/`SkipReport` to `Metrics.cs` for declaring intentionally skipped declarations with reasons
- Extended `ModuleMetrics` with `AudCov` column (`Bound / (Parsed - Skipped)`)
- Implemented `CollectSkips` across all modules: Sokol (10), StbImage, ImGui, Miniaudio, Box2D — all 14 modules at 100% AudCov
- Files: `IModule.cs`, `Metrics.cs`, `Program.cs`, `SokolModule.cs`, 5 Sokol modules, `ImguiModule.cs`, `MiniaudioModule.cs`, `Box2dModule.cs`, `StbImageModule.cs`
- Tests: 338 Generator.Tests pass
- What went well: dynamic skip generation (iterating parsed AST against bound set) avoids maintaining static skip lists that go stale
- Decisions: AudCov capped at 100% for items both bound and skipped. Overload-aware skip counting for ImGui
- Remaining: none
