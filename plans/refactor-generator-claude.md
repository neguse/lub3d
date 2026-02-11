# Generator アーキテクチャ設計方針

## Context

Generator は Clang AST から Lua バインディング (C + LuaCATS) を自動生成するパイプライン。現在 15 モジュールを扱い、今後も増える見込み。

「共通化タスクリスト」ではなく、まず**本質的にどうあるべきか**を定める。

## あるべきアーキテクチャ

```
[入力層]           [中心]              [出力層]
ClangAst.Types ──→ BindingType ←── CBindingGen (C コード文字列)
TypeRegistry       ModuleSpec    ←── LuaCatsGen (LuaCATS 文字列)
                      ↑
                  各 Module の
                  BuildSpec()
```

**原則: ModuleSpec / BindingType がアーキテクチャの中心。入力層 (ClangAst) と出力層 (CBinding, LuaCats) はこの中心にのみ依存する。互いに直接依存してはならない。**

これはクリーンアーキテクチャの依存性逆転: 末端 (パーサー、コード生成器) が中心 (ドメインモデル) に依存し、中心は末端を知らない。

### 現状とのギャップ

この構造は**既に半分できている**:
- `LuaCatsGen.Generate(ModuleSpec)` は BindingType → LuaCats.Type → 文字列 (正規ルート)
- `CBindingGen.Generate(ModuleSpec)` も BindingType ベースで動く (正規ルート)
- 各 Module の `BuildSpec()` は ClangAst.Types → BindingType の変換を行い ModuleSpec を返す

問題は**旧経路が並走していること**:

| 旧経路 (Pipeline.cs) | 迂回内容 | 正規ルート |
|---|---|---|
| `Pipeline.ToCType(ClangAst.Types)` | ClangAst → CBinding.Type 直接変換 | ClangAst → BindingType (各Module) → C文字列 (CBindingGen) |
| `Pipeline.ToLuaCatsType(ClangAst.Types)` | ClangAst → LuaCats.Type 直接変換 | ClangAst → BindingType (各Module) → LuaCats.Type (LuaCatsGen) |
| `Pipeline.ToCFieldInits()` / `ToCParams()` / `ToCReturnType()` | ClangAst → CBinding レコード直接生成 | 未使用 (既に ModuleSpec 経由に移行済み) |
| `CBinding.Type` 階層全体 | BindingType と並存する旧型システム | BindingType |
| `CBindingGen.Func()` / `GenParamDecl()` / `GenPush()` / `GenSet()` | CBinding.Type で動く旧 API | BindingType ベースの `Generate(ModuleSpec)` 内ロジック |

## 設計判断

### 1. BindingType がアーキテクチャの唯一の型表現である

ClangAst.Types は「入力層の内部型」、LuaCats.Type は「出力層の内部型」。
Module 境界を越えるのは **BindingType だけ**。

→ CBinding.Type は BindingType と役割が重複しており、削除する。
→ Pipeline.cs から `ToCType`, `ToCFieldInits`, `ToCParams`, `ToCReturnType` を削除する。
→ Pipeline.cs の `ToLuaCatsType`, `ToLuaCatsFields` 等も削除する (LuaCatsGen.ToLuaCatsType(BindingType) が正規ルート)。

### 2. Pipeline.cs は文字列ヘルパーに徹する

Pipeline.cs の責務を「型変換ハブ」から「文字列ユーティリティ」に限定する:
- `ToPascalCase`, `StripPrefix`, `StripTypeSuffix`, `EnumItemName` — 残す
- `ToCType`, `ToLuaCatsType` 等の型変換系 — 削除

### 3. CBindingGen の公開 API は `Generate(ModuleSpec)` のみ

現状 `CBindingGen` は `StructNew()`, `Func()`, `Enum()` 等を public static メソッドとして公開し、テストから直接呼ばれている。これらは `CBinding.Type` / `Param` / `FieldInit` に依存する旧 API。

→ `Generate(ModuleSpec)` を唯一の public エントリポイントとし、内部メソッドは private にする。
→ テストは ModuleSpec を組み立てて `Generate()` の出力を検証する形に移行。

### 4. 各 Module は「ClangAst → ModuleSpec」の変換器

Module の責務は明確: TypeRegistry (ClangAst のインデックス) を受け取り、ModuleSpec を返す。
Module は CBindingGen も LuaCatsGen も知らない。

→ ImguiModule も IModule 準拠にし、この契約を守る。

### 5. 特殊処理は ModuleSpec のフィールドで表現する

`sg_range` の特殊処理のように「CBindingGen が特定の型名をハードコードしてチェックする」パターンは、ModuleSpec に適切なフィールドを追加して Module 側から宣言する。CBindingGen は型名を見ない。

## リファクタリング (最小限、本質的なもののみ)

上記の設計判断を実現するための作業。YAGNI に基づき、「あるべき姿に向けて旧経路を除去する」ことだけを行う。共通ヘルパーの抽出や Program.cs のリファクタ等の「便利だが本質的でない改善」は行わない。

### Step 1 — CBindingGen 内部の型統一

CBindingGen 内の旧 API (`Func()`, `GenParamDecl()`, `GenPush()`, `GenSet()`, `GenFieldInit()`) が使う `CBinding.Type` / `Param` / `FieldInit` を `BindingType` ベースに書き換える。

- `GenParamDecl` と `GenOpaqueParamDecl` を BindingType ベースの単一メソッドに統合
- 戻り値 push を `GenReturnPush(BindingType, callExpr)` に統合
- `FieldInit.Type` を `BindingType` に変更

**BindingType 別の挙動契約 (差分ゼロの保証):**

| BindingType | パラメータ生成 | 戻り値 push | フィールド Init | フィールド Index | フィールド NewIndex |
|---|---|---|---|---|---|
| **Custom** | CheckCode 展開 | PushCode 展開 (null なら return 0) | → Type.Struct → lua_pop (初期化しない)。PushCode/SetCode のみ効く | PushCode 展開 (null なら lua_pushnil) | SetCode 展開 (null なら unsupported error) |
| **Callback** | **パラメータ/戻り値**: `spec.Funcs` に Callback パラメータまたは Callback 戻り値を持つ関数が含まれていた場合は **hard error** (例外送出)。Module 側で除外すべきであり、CBindingGen は不正な入力を受け付けない。Callback 付き関数は `ExtraLuaFuncs` (LuaCATS専用) + `ExtraCCode` (手書きC) で扱う。**フィールド**: `lua_pop(L,1)` のみ (初期化しない)。Index/NewIndex/Pairs からフィルタ除外 (`is Callback`) | 同左 | `lua_pop(L,1)` のみ | Index/NewIndex/Pairs からフィルタ除外 (`is Callback`) | 同左 |
| **FixedArray(Struct)** | N/A (フィールド専用。C の配列パラメータは `Types.Ptr` にdecayするため FixedArray にならない。万一パラメータに出現した場合は **hard error**) | N/A | `GenerateArrayFieldInit` でループ生成 | lua_pushnil | unsupported type error |
| **FixedArray(その他)** | 同上 | N/A | `lua_pop` のみ | lua_pushnil | unsupported type error |
| **Struct** | `luaL_checkudata` (ConstPtr(Struct) は const 付き) | userdata 生成 + `luaL_setmetatable` | 自動構築 (l_CName_new + luaL_checkudata) | Push: userdata コピー | Set: table→new または直接 checkudata |

**基本型のマッピング (CBinding.Type → BindingType 直接処理):**

CBinding.Type 削除後、CBindingGen 内で BindingType を直接 switch する。以下は既存の CBinding.Type と BindingType の対応:

| CBinding.Type | BindingType | パラメータ (luaL_check*) | 戻り値 (lua_push*) |
|---|---|---|---|
| Type.Int | Int | `luaL_checkinteger` | `lua_pushinteger` |
| Type.Float | Float | `luaL_checknumber` (cast float) | `lua_pushnumber` |
| Type.Double | Double | `luaL_checknumber` | `lua_pushnumber` |
| Type.Bool | Bool | `lua_toboolean` | `lua_pushboolean` |
| Type.String | Str | `luaL_checkstring` | `lua_pushstring` |
| Type.Pointer(Void) | VoidPtr | `lua_touserdata` | `lua_pushlightuserdata` |
| Type.Pointer(t) | Ptr(t) | 型依存 | 型依存 |
| Type.ConstPointer(t) | ConstPtr(t) | 型依存 (const 付き) | 型依存 |
| Type.Enum | Enum | `luaL_checkinteger` (cast) | `lua_pushinteger` |
| Type.Struct | Struct | `luaL_checkudata` | userdata コピー + setmetatable |
| Type.UInt | UInt32 | `luaL_checkinteger` (cast) | `lua_pushinteger` |
| Type.Size | Size | `luaL_checkinteger` (cast) | `lua_pushinteger` |
| — | Int64 / UInt64 | `luaL_checkinteger` (cast) | `lua_pushinteger` |
| — | Vec2 / Vec4 / FloatArray | ImGui 専用 (GenCppParamDecl) | ImGui 専用 |

この表は Step 1 のテスト検証に使う。各型のパラメータ・戻り値生成が CBinding.Type 削除後も同一出力であることを確認する。

**対象**: `Generator/CBinding/CBindingGen.cs`, `Generator/CBinding/CBinding.cs`
**検証**: `dotnet test Generator.Tests`

### Step 2 — CBinding.Type 削除、Pipeline.cs の型変換系削除

旧型システムとそれに依存する全経路を削除:
- `CBinding.Type` 階層、`Param` (CheckCode付き) レコードを削除
- `CBindingGen.ToOldType()` ブリッジを削除
- `CBindingGen.Func()` 等の旧 public API を private 化または削除
- `Pipeline.ToCType()`, `ToCFieldInits()`, `ToCParams()`, `ToCReturnType()` を削除
- `Pipeline.ToLuaCatsType()`, `ToLuaCatsFields()`, `ToLuaCatsParams()`, `ToLuaCatsReturnType()`, `ToLuaCatsFuncName()`, `ToLuaCatsEnumName()` を削除 (LuaCatsGen.ToLuaCatsType(BindingType) が正規ルート)。これらは全てテスト (`Generator.Tests/GenLuaCATSTests.cs`) からのみ参照されており、プロダクションコードでは未使用
- 参照元のテストを ModuleSpec ベースに更新。`LuaCatsGen.ToLuaCatsType` は `internal static` であり `InternalsVisibleTo` もないため、テストからは `LuaCatsGen.Generate(ModuleSpec)` 経由で出力文字列を検証する形に移行する（直接呼び出しは不可）

**対象**: `Generator/CBinding/CBinding.cs`, `Generator/CBinding/CBindingGen.cs`, `Generator/Pipeline.cs`, `Generator.Tests/` の関連テスト
**検証**: `dotnet test Generator.Tests` + `scripts\build.bat win-dummy-debug` + `scripts\run_tests.bat`

### Step 3 — ImguiModule の IModule 準拠

ImguiModule を IModule 実装にする。

- `IModule` を実装し、`Prefix = ""` を設定（ImGui は C++ namespace ベースで C prefix を持たないため。`IModule.Prefix` は `prefixToModule` 辞書構築と `CreateView` の `IsDep` 判定に使われるが、ImGui はどちらも不要）
- `GenerateC(TypeRegistry, Dict)` / `GenerateLua(TypeRegistry, Dict, SourceLink?)` のシグネチャに合わせる
- **データパス**: 現在の `BuildSpec(Module)` は `module.Decls` のみ参照している（L45, L49）。`TypeRegistry` は内部に `Module` を保持し `AllDecls` プロパティで同じ `Decl` リストにアクセスできるため、`BuildSpec(Module)` → `BuildSpec(TypeRegistry)` に変更し、`module.Decls` → `reg.AllDecls` に置き換えるだけでよい
- `ModuleSpec.Prefix` も `""` のまま。`prefixToModule` 辞書には参加しない（Program.cs の独立ブロックで処理）
- **注**: Program.cs の `ParseCppHeadersWithRawJson` に渡す namespace `["ImGui"]` は clang++ パーサーへの指示であり、`IModule.Prefix`（C 関数名の prefix）とは別概念。将来 C++ namespace ベースのモジュールが増えた場合に `IModule` に `Namespaces` プロパティを追加して統合する
- Program.cs 側: `TypeRegistry.FromModule(imguiParsed)` で TypeRegistry を作り、`imguiModule.GenerateC(reg, ...)` / `imguiModule.GenerateLua(reg, ...)` を呼ぶ形に変更
- 生成ファイル diff なし（ModuleSpec の内容は変わらないため）

**対象**: `Generator/Modules/Imgui/ImguiModule.cs`, `Generator/Program.cs`
**検証**: `dotnet test Generator.Tests` + 生成ファイル diff なし

### Step 4 — sg_range 特殊処理を ModuleSpec に移動

CBindingGen 内の `sg_range` 名前ハードコードを全箇所除去。`StructBinding` に `bool AllowStringInit = false` を **default 付きパラメータ**として追加し、Module 側から宣言する。default 付きなので既存の call site（SokolModule.cs L56, Box2dModule.cs L347）はコード変更不要。SokolModule の sg_range 構造体のみ `AllowStringInit: true` を明示的に設定する。

`sg_range` の名前判定は **3 箇所**:
1. **`Generate()` L310**: `s.CName == "sg_range"` → `s.AllowStringInit` で分岐 (SgRangeNew vs StructNew)
2. **`ToFieldInit()` L948**: フィールド型の `cName == "sg_range"` → フィールド型に対応する StructBinding の `AllowStringInit` を参照
3. **`GenerateArrayFieldInit()` L992**: 配列要素型の `cName == "sg_range"` → 呼び出し元から `allowStringInit` パラメータで渡す

**伝播方法**: 箇所 2・3 は「フィールドの型」が sg_range かどうかを判定している（親構造体ではない）。そのため `ToFieldInit` のシグネチャを変更する:
- `ownStructs: HashSet<string>` → `structBindings: Dictionary<string, StructBinding>`
- フィールド型が `BindingType.Struct(cName, ...)` のとき `structBindings.TryGetValue(cName, out var sb)` で参照。辞書に無い場合は `AllowStringInit = false` 扱い。これは意図的: `structBindings` は `spec.Structs` から構築するため own struct のみ含む。外部モジュールの同名構造体がフィールドに現れても string init は有効にならない（そもそも外部の構造体は `ownStructs.Contains` チェックで auto-construct 対象外であり、既存挙動と一致する）
- `GenerateArrayFieldInit` にも `bool allowStringInit` パラメータを追加し、同じ辞書から引いた値を渡す

`AllowStringInit` のデフォルトは `false` なので既存の全 call site に影響なし。

**注意**: `AllowStringInit` は `lua_isstring` 条件の追加のみを制御する。`AllowStringInit = false` でも own struct フィールドの `lua_istable` による auto-construct（`l_CName_new` 呼び出し）は従来通り維持される。つまり `AllowStringInit` は既存の `lua_istable` 条件に `|| lua_isstring` を**追加する**フラグであり、`lua_istable` を**置き換える**フラグではない。

**対象**: `Generator/ModuleSpec.cs` (StructBinding), `Generator/CBinding/CBindingGen.cs` (3 箇所 + ToFieldInit シグネチャ変更), `Generator/Modules/Sokol/SokolModule.cs`
**検証**: `dotnet test Generator.Tests` + 生成ファイル diff なし

## やらないこと

- Program.cs のオーケストレーション共通化 (便利だが本質的でない)
- GetLink 等の共通ヘルパー抽出 (重複は 8 行、抽出のコスト > メリット)
- BuildSpec ユーティリティの共有化 (各 Module の多様性を制約する)
- ExtraCCode の外部ファイル化 (raw string literal で十分)
- LuaCats.Type と BindingType の統合 (出力層の内部型として適切に分離されている)
- 未知型の網羅的な診断ログ基盤 (BindingType.Unknown 導入や Void fallthrough への警告付加等)。ただし Callback パラメータ検出のような「不正な ModuleSpec に対する防御的スキップ」は Step 1 で行う

## 検証手順 (各 Step 完了時)

1. `dotnet test Generator.Tests` — テスト全通過
2. `dotnet run --project Generator -- gen --deps deps --clang clang` — 生成実行
3. 生成ファイルの `git diff` — 差分なし
4. `scripts\build.bat win-dummy-debug` — ビルド成功
5. `scripts\run_tests.bat` — ヘッドレステスト全通過

## 追加すべきテスト

- **Step 1**: Callback パラメータ / 戻り値 / FixedArray パラメータを持つ関数を `spec.Funcs` に入れた ModuleSpec で `Generate()` を呼ぶと例外が発生することを検証するテスト
- **Step 1**: 基本型マッピング表の各型（Int, Float, Double, Bool, Str, VoidPtr, Ptr, ConstPtr, Enum, Struct, UInt32, Size）についてパラメータ・戻り値生成が正しいことを検証する最小テスト
- **Step 3**: ImGui の imgui_gen.cpp / imgui.lua が非空であり、IModule 変更前後で diff がないことを確認するスモークテスト
- **Step 4**: `AllowStringInit = true` の StructBinding が string 条件付きコンストラクタを生成し、`AllowStringInit = false`（デフォルト）の StructBinding が通常コンストラクタを生成することを検証するテスト
