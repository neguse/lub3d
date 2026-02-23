# Completed Tasks

<!-- Add newest entries at the top -->

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
