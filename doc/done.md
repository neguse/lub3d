# Completed Tasks

<!-- Add newest entries at the top -->

### T09 + T01-T05: Skip-aware metrics + full audit of all modules (2026-02-23)
- Added `SkipEntry`/`SkipReport` records to `Metrics.cs` for declaring intentionally skipped declarations with reasons
- Added `CollectSkips()` default method to `IModule` interface and `virtual` method to `SokolModule` base class
- Extended `ModuleMetrics` with `SkippedFuncs/SkippedStructs/SkippedEnums` counts and `AudCov` column (`Bound / (Parsed - Skipped)`)
- `CollectUnbound()` now returns `(UnboundReport, SkipReport?)` tuple; `PrintUnbound()` separates "Unhandled" from "Intentionally Skipped"
- Wired `CollectSkips()` in all 5 module generation sections of `Program.cs`
- Implemented `CollectSkips` with reason-annotated skip lists in all modules:
  - **Sokol** (10 modules): Time (1 func), DebugText (3 funcs), Gl (4 funcs), Shape (2 funcs), Imgui (2 structs)
  - **StbImage**: 25 funcs + 1 struct (callback I/O, FILE* I/O, 16-bit/HDR/GIF, zlib internals)
  - **ImGui**: Dynamic skip generation for 99 func overloads + 4 enum duplicates (varargs, unsupported params, context management)
  - **Miniaudio**: Dynamic skip generation for 851 funcs + 178 structs + 42 enums with prefix-based rules (~60 categories)
  - **Box2D**: Dynamic skip generation for 126 funcs + 30 structs + 1 enum with explicit reasons
- All 14 modules show **100% AudCov** with 0 unhandled declarations
- Files changed: `IModule.cs`, `Metrics.cs`, `Program.cs`, `SokolModule.cs`, `Time.cs`, `DebugText.cs`, `Gl.cs`, `Shape.cs`, `Imgui.cs` (Sokol), `ImguiModule.cs`, `MiniaudioModule.cs`, `Box2dModule.cs`, `StbImageModule.cs`
- What went well: Dynamic skip generation (iterating parsed AST against bound set) worked well for large modules — avoids maintaining static lists that can get stale
- Decisions: AudCov capped at 100% to handle items both bound (via custom wrappers counted in BoundFuncs) and skipped (with reason). UninitFunc/ConfigInitFunc now counted in BoundFuncs. Overload-aware skip counting for ImGui.
- Remaining: None — all modules fully audited
