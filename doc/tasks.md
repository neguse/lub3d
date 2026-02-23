# Tasks

## Pending

<!-- Template:
### Task name
- Background: why this task exists
- Requirements: what "done" looks like
- Approach: chosen design, affected components, key trade-offs
- Alternatives rejected: other options and why they were dropped
-->

<!-- T09, T01-T06 completed — see doc/done.md -->

<!-- ==================== Lint cleanup ==================== -->

### T10: lubs check 警告の修正 (60件)
- Background: lubs check (severity: warning) で 63件の診断。うち 3件は lubs 側の型定義精度の問題で lub3d 対処不要。残り 60件が lub3d 側の対処事項。
- Requirements: lubs check 再実行で lub3d 側の警告 0件。lubs 側の 3件 (assign_type_mismatch, param_type_mismatch x2) は残存 OK。
- Approach: カテゴリ別に一括修正
  1. **未使用 require 削除** (9件): `lib/sprite.lua:5` glue, `lib/render_pass.lua:3` gfx, `examples/hakonotaiatari/{field.lua:4, init.lua:10, record.lua:3}`, `examples/rhythm/{song/scanner.lua:4, test/test_integration.lua:7, test/test_judge.lua:3}`, `examples/rendering/ctx.lua:4` app
  2. **未使用パラメータ `_` リネーム** (26件): `lib/headless_app.lua` (14件 — スタブ関数引数), `lib/audio.lua:27` handle, `examples/hakonotaiatari/{enemy.lua:361 dt, field.lua:45 angle, renderer.lua:47 vx/vy/vz, title.lua:85 audio, tutorial.lua:15,79 audio}`, `examples/rendering/lighting.lua:345` ctx, `examples/rhythm/{game/playfield.lua:72 current_beat, init.lua:94 judgment, init.lua:97 note, init.lua:216 path}`, `examples/sjadm/player.lua:188` iy
  3. **未使用変数の削除/整理** (14件): `lib/gpu.lua:12` gc_supported → `local _ = ...`, `lib/render_pipeline.lua:46` missing → `_missing`, `examples/hakonotaiatari/{game.lua:194-195 gauge_width/height 削除, renderer.lua:40 hash関数 削除}`, `examples/rendering/light.lua:68` moonlight_color0 削除, `examples/rhythm/audio/manager.lua:10` log_warn 削除, `examples/cna/init.lua:21` RESERVE_NUM 削除, `examples/imgui_test.lua:3` app → `require("sokol.app")`
  4. **sprite.lua GC アンカー宣言削除** (2件): `lib/sprite.lua:96-97` shared_shader_ref / shared_pipeline_ref — 宣言のみで未代入。raw ハンドルがモジュールレベル変数に保持されるため GC アンカー不要
  5. **shadowed_variable リネーム** (1件): `examples/rendering/init.lua:280` `local t1, t2, t3` → `local tan1, tan2, tan3` (外側の t1=os.clock() との混同防止。バグではないが紛らわしい)
  6. **global_usage 抑制** (1件): `lib/headless_app.lua:7` `_headless_frames` に `---@diagnostic disable-next-line: global_usage`
- Alternatives rejected: shadowed_variable 全件リネーム — encoding.lua の b2/b3 や rhythm/init.lua の ok/err は排他ブランチ内で無害、リネームのほうがリスクあり
- lubs 側の問題 (対処しない 3件):
  - `examples/miniaudio_test.lua:12` assign_type_mismatch — インライン `---@type` 非対応
  - `examples/rhythm/bms/encoding.lua:64` param_type_mismatch — math.floor 戻り値型
  - `examples/rhythm/song/scanner.lua:66` param_type_mismatch — 関数サブタイピング

<!-- ==================== Phase 2-impl: Ownership model implementation (designed in T06) ==================== -->

### T06-impl: Generator ownership 抽象の実装
- Background: T06 の調査・設計フェーズ完了 (doc/ownership-research.md, doc/ownership-design.md)。設計指針に基づき ModuleSpec / CBindingGen / LuaCatsGen を拡張する。
- Requirements: `DependencyBinding` と `HasExplicitDestroy` を実装。miniaudio モジュールで PoC (ma_sound → ma_engine 依存追跡、destroy メソッド生成)。全既存テスト + 新規テスト通過。
- Approach: doc/ownership-design.md の設計に従う。ModuleSpec.cs に `DependencyBinding` レコード追加、`OpaqueTypeBinding` に `Dependencies` / `HasExplicitDestroy` フィールド追加 (デフォルト値で後方互換)。CBindingGen で uservalue スロット生成と destroy メソッド生成。LuaCatsGen で destroy アノテーション。MiniaudioModule で ExtraCCode の ma_sound_new に engine 参照保持を追加。
- Alternatives rejected: WASI の num_lends カウンタ方式 — Lua シングルスレッドでは過剰
- Depends on: T06 (completed)

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
Phase 2 (completed):            T06 (research + doc)
Lint cleanup:                   T10
Phase 2-impl (next):            T06-impl
Phase 3 (after T06-impl):      T07 → T08
```

T10 は独立して実行可能。T06-impl は T10 と並行可能だが、同一ブランチで進める場合は T10 を先に片付けるのが効率的。
Phase 3 tasks are ordered: Jolt before ozz, since Jolt is simpler C++ binding (no SoA) and lessons learned carry over.

## Completed

See `doc/done.md`.
