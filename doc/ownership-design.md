# Generator Ownership 設計指針

T06 の調査結果 (`doc/ownership-research.md`) に基づく、Generator の ownership 抽象改善の設計指針。

## 設計原則

1. **粉砕前提**: 後方互換は維持しない。既存モジュールの呼び出し側はその場で直す
2. **実用重視**: ゲームフレームワークであり安全クリティカルシステムではない。過剰な安全機構より開発体験を優先

## 提案: ModuleSpec 変更

### A. DependencyBinding (依存ライフタイム)

sol3 の `self_dependency` パターンを採用。子オブジェクトの uservalue スロットに親への Lua 参照を格納し、親が先に GC されるのを防ぐ。

```csharp
/// 親子ライフタイム依存: コンストラクタ引数を uservalue スロットに保持
public record DependencyBinding(
    int ConstructorArgIndex,  // コンストラクタでの Lua スタックインデックス
    int UservalueSlot,        // 1-indexed uservalue スロット番号
    string Name               // 可読名 ("engine" 等)
);
```

`OpaqueTypeBinding` に `Dependencies` フィールドを追加 (non-nullable、空リスト = 依存なし):

```csharp
public record OpaqueTypeBinding(
    ... 既存フィールド ...,
    List<DependencyBinding> Dependencies  // 空リスト = 依存なし
);
```

既存の全 OpaqueTypeBinding 生成箇所に `Dependencies: []` を追加。

#### 生成される C コード

Dependencies が空の場合は従来通り uservalue 0。Dependencies がある場合:

```c
ma_sound** pp = (ma_sound**)lua_newuserdatauv(L, sizeof(ma_sound*), 1);
*pp = p;
luaL_setmetatable(L, "miniaudio.Sound");
lua_pushvalue(L, 1);          // engine 引数をコピー
lua_setiuservalue(L, -2, 1);  // uservalue slot 1 に格納
return 1;
```

engine は sound の uservalue に格納されるため、sound が生きている限り engine は GC されない。

### B. destroy メソッドの自動生成

`UninitFunc != null` を持つ全 OpaqueType に `destroy()` メソッドを **常に生成** する。フラグ不要。

`__gc` と同じロジックを Lua メソッドとして公開:

```c
static int l_ma_engine_destroy(lua_State *L) {
    ma_engine** pp = (ma_engine**)luaL_checkudata(L, 1, "miniaudio.Engine");
    if (*pp != NULL) {
        ma_engine_uninit(*pp);
        free(*pp);
        *pp = NULL;
    }
    return 0;
}
```

メソッドテーブルに自動追加:
```c
static const luaL_Reg ma_engine_methods[] = {
    {"destroy", l_ma_engine_destroy},
    {"start", l_ma_engine_start},
    ... 既存メソッド ...
    {NULL, NULL}
};
```

LuaCATS にも自動追加:
```lua
---@class miniaudio.Engine
---@field destroy fun(self: miniaudio.Engine)
---@field start fun(self: miniaudio.Engine): miniaudio.Result
```

Lua 側の使い方:
```lua
local engine = ma.engine_init()
-- ... 使用 ...
engine:destroy()  -- 決定的に解放 (__gc は NULL チェックで no-op になる)
```

## 変更対象ファイル

### CBindingGen.cs

| メソッド | 変更内容 |
|---------|---------|
| `OpaqueConstructor()` | Dependencies.Count に応じて uservalue スロット数変更 + `lua_setiuservalue` 生成 |
| `OpaqueDestructor()` | 変更なし (既存の NULL チェックで destroy 後の __gc は no-op) |
| `OpaqueMethodTable()` | UninitFunc != null なら destroy エントリを常に追加 |
| (新規) `OpaqueDestroyMethod()` | destroy メソッド関数生成 (__gc と同じ本体) |

### LuaCatsGen.cs

opaque type class 生成セクションで、UninitFunc != null なら `---@field destroy` を常に追加。

### MiniaudioModule.cs

1. `OpaqueTypeBinding` 生成箇所に `Dependencies: []` を追加
2. `ExtraCCode()` の `l_ma_sound_new` で:
   - `lua_newuserdatauv` の uservalue 数を 0 → 1
   - `luaL_setmetatable` 後に engine 参照を uservalue に格納

### 既存モジュールの修正

全ての OpaqueTypeBinding 生成箇所に `Dependencies: []` を追加。

## スコープ外 (実装しないもの)

| 項目 | 理由 |
|------|------|
| `num_lends` カウンタ (WASI 方式の borrow 追跡) | 過剰。uservalue 参照保持で十分 |
| Handle 型の自動 destroy マッピング | `lib/gpu.lua` の Lua ラッパーパターンで十分機能している |
| `ParamOwnership` の C コード生成反映 | 現時点で実害なし。T07/T08 で必要になったら追加 |
| スレッドセーフティ / borrow スコープ検証 | Lua はシングルスレッド |

## T07 (Jolt Physics) への展望

Jolt は `Ref<T>` (参照カウント) を使用:

- `DependencyBinding`: `Body` → `PhysicsSystem` 依存を表現
- `HasExplicitDestroy`: physics body の明示的除去に必要
- `unique_usertype_traits` 相当の拡張: `Ref<T>` を `BindingType` に追加し、is_null チェック + 参照カウント連携

## T08 (ozz-animation) への展望

ozz は span ベース API:

- `DependencyBinding`: `SamplingJob` 出力が `Animation` / `Skeleton` に依存
- borrow 的パラメータ: span は関数呼び出し中のみ有効 → 現行の値コピーパターンで対応可能
- SoA (Structure of Arrays) ラッパー: ownership ではなくデータレイアウトの問題、別途対応

## テスト戦略

実装時には以下のテストを追加:

**OpaqueTypeGenTests.cs**:
- `C_HasExplicitDestroy_GeneratesDestroyMethod`
- `C_HasExplicitDestroy_MethodTableContainsDestroy`
- `Lua_HasExplicitDestroy_ContainsDestroyField`
- `C_Dependencies_GeneratesUservalueSlots`
- `C_DefaultDependencies_BackwardCompatible`

**MiniaudioModuleTests.cs**:
- `BuildSpec_Engine_HasExplicitDestroy`
- `BuildSpec_Sound_HasExplicitDestroy`
- `GenerateC_Sound_StoresEngineReference`
- `GenerateLua_Engine_HasDestroyMethod`
