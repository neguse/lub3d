# Ownership Model Research: sol3 / WASI Component Model

T06 の一環として、Lua バインディングにおける ownership モデルの先行事例を調査した。

## 1. sol3 (C++/Lua バインディングライブラリ)

### 1.1 3つの ownership カテゴリ

sol3 は C++ オブジェクトを Lua に渡す際、3つの ownership モデルを使い分ける。

**A. Value semantics (Lua 所有)**

```
メモリレイアウト: [T* pointer | T data]  ← Lua userdata 内
```

- オブジェクトが **コピーまたはムーブ** されて Lua 管理メモリに格納される
- GC が userdata を回収するとき C++ デストラクタ (`__gc`) を呼ぶ
- **最も安全**: ダングリング参照が原理的に発生しない

トリガー条件:
- 値返し (`return T`)
- `lua["x"] = value` (コピー代入)
- ラムダの暗黙 auto 戻り値 (decay → コピー)

**B. Reference semantics (C++ 所有)**

```
メモリレイアウト: [T* pointer のみ]  ← Lua userdata 内
```

- **`__gc` を生成しない** — C++ 側がライフタイムを管理する前提
- raw pointer は常に non-owning として扱われる (`delete` しない)
- **use-after-free リスク** あり — C++ 側でオブジェクトが破棄されると Lua 側が壊れる

トリガー条件:
- ポインタ返し (`return T*`)
- 明示的参照返し (`-> T&`)
- `std::ref(obj)` ラッパー

**C. Smart pointer semantics (所有権の移転/共有)**

```
メモリレイアウト: [T* pointer | deleter | T data]
```

- `unique_ptr<T>`: Lua が排他所有。GC 時に deleter が実行される
- `shared_ptr<T>`: 参照カウント維持。GC 時に refcount デクリメント、0 で破棄
- どちらも `__gc` が生成される

### 1.2 所有権決定ルール

**C++ の戻り値型が所有権を決定する** — これが sol3 の中核設計:

| 戻り値型 | 所有権 | `__gc` | 安全性 |
|----------|--------|--------|--------|
| `T` (値) | Lua 所有コピー | あり | 安全 |
| `T&` / `T*` | C++ 所有 | なし | 危険 |
| `unique_ptr<T>` | Lua 排他所有 | あり | 安全 |
| `shared_ptr<T>` | 共有 (refcount) | あり | 安全 |

### 1.3 依存ライフタイムの追跡

sol3 は `sol::policies` で親子ライフタイムを管理する:

- **`sol::self_dependency`**: 子 userdata に親への Lua 参照を付与 → 親が先に GC されるのを防ぐ
- **`sol::returns_self`**: メソッドが self を返す (チェーン呼び出し用)
- **`sol::stack_dependencies`**: 任意のスタックオブジェクト間の依存関係を宣言

```cpp
lua.new_usertype<Parent>("Parent",
    "get_child", &Parent::get_child,
    sol::policies(sol::self_dependency)  // child → parent 参照を保持
);
```

### 1.4 `unique_usertype_traits<T>` 拡張ポイント

カスタム handle / smart pointer 型を sol3 に登録するための traits:

```cpp
template <typename T>
struct unique_usertype_traits {
    typedef T type;
    typedef T actual_type;
    static const bool value = false;
    static bool is_null(const actual_type&);
    static type* get(const actual_type&);
};
```

`is_null()` が true を返すと sol3 は `nil` を push する。Jolt の `Ref<T>` 等に応用可能。

## 2. WASI Component Model

### 2.1 Resource 型と Handle

WASI では resource はコピーできないエンティティ。常に **handle** (整数インデックス) 経由でアクセスする。

2つの handle 型:

- **`own<T>`**: 排他所有ハンドル。drop 時にデストラクタ呼び出し
- **`borrow<T>`**: 一時貸出ハンドル。現在のエクスポート呼び出しが終了するまでに drop 必須

### 2.2 Handle Table

各コンポーネントインスタンスが固有の handle table を持つ:

```
HandleTable: [index → ResourceHandle]
ResourceHandle: { rt: ResourceType, rep: i32, own: bool, num_lends: int }
```

- `num_lends`: この handle から貸し出し中の borrow 数
- **own ハンドルは num_lends > 0 のとき drop できない** → use-after-free を防止

### 2.3 所有権移転 (Lift/Lower)

**own の移転**:
1. Source: handle table から **remove** (以後アクセス不可)
2. Destination: handle table に **add** (新しい所有者)
→ 2つのコンポーネントが同時に own することはない

**borrow の貸出**:
1. Source: handle table から **get** (remove しない)、`num_lends++`
2. Destination: borrow handle を table に add (scope 付き)
3. 呼び出し完了時: `num_lends--`

### 2.4 WIT の設計パターン

```wit
resource blob {
    constructor(init: list<u8>);       // → own<blob> を返す
    write: func(bytes: list<u8>);      // borrow<self> を取る
    read: func(n: u32) -> list<u8>;    // borrow<self> を取る
    merge: static func(lhs: blob, rhs: blob) -> blob;  // own を取り own を返す
}
```

原則:
- **Constructor** は常に `own<T>` を返す
- **Method** は常に `borrow<self>` を取る
- **Static function** は任意の所有権パターン

### 2.5 明示的 drop

WASI は GC に依存しない設計。`resource.drop` が主要な破棄手段:
- 最後の `own<T>` の drop がデストラクタを呼ぶ
- GC は存在しない (明示的 acyclic ownership)

## 3. 現行 Generator との対応

| Generator パターン | sol3 対応 | WASI 対応 | 備考 |
|-------------------|-----------|-----------|------|
| **ValueStruct** (StructBinding) | Value semantics | Plain data (handle なし) | stack 格納、`__gc` 不要 |
| **OpaqueType** (OpaqueTypeBinding) | unique ownership | `own<T>` | heap 格納、`__gc` で uninit+free |
| **HandleType** (IsHandleType) | Reference semantics | `borrow<T>` (概念的) | 値コピー、C 側がリソース管理 |

### 3.1 Generator の OpaqueType ライフサイクル

```
1. malloc(sizeof(T))           → ヒープ割り当て
2. init_func(&config, p)       → リソース初期化
3. lua_newuserdatauv(sizeof(T*)) → ポインタを userdata に格納
4. luaL_setmetatable(metatable) → メタテーブル設定
5. [使用中] check_T(L, idx) でNULLチェック
6. __gc → uninit_func(*pp); free(*pp); *pp = NULL;
```

## 4. ギャップ分析

### Gap 1: 依存ライフタイム追跡がない (高優先度)

**問題**: `ma_sound` は内部で `ma_engine` を参照する。engine が先に GC されると sound がクラッシュする。

**現状の回避策**: `lib/audio.lua` でユーザーが手動で engine と vfs の参照を保持している。

**sol3 の解決策**: `sol::self_dependency` — 子 userdata の uservalue に親への参照を格納。

**WASI の解決策**: `num_lends` カウンタ — 貸出中のリソースは drop できない。

**推奨**: sol3 方式 (uservalue スロット) が Lua に自然にマッピングされる。Lua 5.5 の `lua_setiuservalue` を使い、コンストラクタで依存オブジェクトの参照を保持する。

### Gap 2: 明示的 destroy() がない (中優先度)

**問題**: `__gc` のみで決定的なリソース解放ができない。GC のタイミングは非決定的。

**現状の回避策**: `lib/gpu.lua` が handle 型をラップして手動 `destroy()` を提供。

**sol3 の解決策**: 明示的デストラクタ + GC の両方をサポート。

**WASI の解決策**: `resource.drop` が主要な破棄手段、GC に依存しない。

**推奨**: OpaqueType に `destroy` メソッドを生成するオプション追加。`__gc` は既存の NULL チェックで二重 free を防止済み。

### Gap 3: パラメータ ownership アノテーションがない (低優先度)

**問題**: `ma_sound_init_from_file(engine, ...)` の `engine` パラメータが borrow であることが型レベルで表現されない。

**影響**: 現時点では実害なし。T07 (Jolt `Ref<T>`) / T08 (ozz span) で必要になる。

**推奨**: `ParamBinding` に ownership アノテーション追加 (ドキュメント用、コード生成は将来)。
