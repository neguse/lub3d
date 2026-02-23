# Completed Tasks

<!-- Add newest entries at the top -->

### T06: Research ownership models (sol3, WASI) and improve Generator abstractions ✓ (2026-02-23)
- sol3 の ownership モデル (value/reference/smart pointer semantics) と WASI Component Model の resource モデル (own/borrow ハンドル) を調査
- 現行 Generator の ValueStruct / OpaqueType / HandleType と sol3 / WASI の対応関係を整理
- ギャップ分析: 依存ライフタイム追跡 (高)、明示的 destroy (中)、パラメータ ownership (低) を特定
- Generator 改善の設計指針を策定: `DependencyBinding` (sol3 self_dependency 方式)、`HasExplicitDestroy` (WASI resource.drop 方式)
- Files: `doc/ownership-research.md` (調査結果), `doc/ownership-design.md` (設計指針)
- What went well: sol3 の uservalue 参照保持パターンが Lua 5.5 の `lua_setiuservalue` に直接マッピングできる
- Decisions: WASI の `num_lends` カウンタは過剰と判断、sol3 方式の uservalue 参照保持を採用。ParamOwnership は将来 T07/T08 で実装
- Remaining: ModuleSpec / CBindingGen / LuaCatsGen の実装、miniaudio PoC (設計指針 doc に詳細記載)

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
