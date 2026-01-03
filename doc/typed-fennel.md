# Typed Fennel Design Doc

Fennelに型アノテーションを追加し、LuaCATSコメントとして出力することで、lua-language-serverによる型チェックを実現する。

## 背景

- FennelはLispシンタックスでLuaにコンパイルされる
- Conjureとの組み合わせで優れたREPL駆動開発が可能
- しかしFennelには型システムがない
- LuaにはLuaCATS + lua-language-serverによる型チェックがある

## 他言語の調査

| 言語 | アプローチ |
|------|-----------|
| Typed Racket | 静的型、モジュール境界に契約生成 |
| Clojure spec/Malli | ランタイム検証、スキーマとしてデータ定義 |
| Common Lisp | `(declare (type integer x))` コンパイラヒント |
| **Hy** | **`^int x` → Python型ヒント出力、mypy使用** |

**Hyのアプローチが最も参考になる**: Fennelで型アノテーションを書き、LuaCATSコメントとして出力する。

## 調査結果: Fennelでのコメント出力

### `(lua)` スペシャルフォーム ✅ 使える

Fennelには`(lua)`スペシャルフォームがあり、生のLuaコード（コメント含む）を出力できる。

```fennel
(lua "---@param x number")
(lua "---@param y number")
(lua "---@return number")
(fn add [x y]
  (+ x y))
```

出力:
```lua
---@param x number
---@param y number
---@return number
local function add(x, y)
  return (x + y)
end
```

### `(comment)` スペシャルフォーム ❌ 使えない

`(comment "...")`はブロックコメント`--[[ ... ]]`のみ出力。LuaCATSは`---@`形式が必要なため不可。

### コンパイラプラグイン ⚠️ 実験的

`pre-fn`フックでdocstring出力可能だが、mainブランチのみで安定版未対応。

## 実装アプローチ

### アプローチ1: `(lua)`マクロラッパー ⭐推奨

```fennel
(macro fn: [name params ret & body]
  (let [annotations []]
    ;; パラメータ型アノテーション生成
    (each [_ p (ipairs params)]
      (table.insert annotations `(lua ,(.. "---@param " (tostring p) " any"))))
    ;; 戻り値型アノテーション
    (when ret
      (table.insert annotations `(lua ,(.. "---@return " ret))))
    `(do ,@annotations (fn ,name ,params ,@body))))

;; 使用例
(fn: add [x y] :number
  (+ x y))
```

**メリット**: シンプル、今すぐ使える、1ファイル完結
**デメリット**: マクロ構文がやや冗長

### アプローチ2: スタブファイル生成

gen_lua.pyと同じパターン。実行コードと型定義を分離。

```
fennel/mymodule.fnl
    ├─→ lib/mymodule.lua      (実行用、型なし)
    └─→ types/mymodule.lua    (型定義のみ)
```

types/mymodule.lua:
```lua
---@meta

---@param x number
---@param y number
---@return number
function add(x, y) end
```

**メリット**: 型とコード分離、既存パターン踏襲
**デメリット**: ビルドステップ追加、同期維持が必要

## 提案する構文

### Option A: シンプルマクロ (推奨)

```fennel
(fn: add [(x number) (y number)] number
  (+ x y))
```

### Option B: インライン型 (Hy風)

```fennel
(fn add [^number x ^number y] -> number
  (+ x y))
```

### Option C: declare (Common Lisp風)

```fennel
(fn add [x y]
  (declare (: x number) (: y number) (-> number))
  (+ x y))
```

## 比較

| 方法 | 実装難易度 | 使いやすさ | メンテ性 |
|------|-----------|-----------|---------|
| `(lua)`マクロ | 低 | 中 | 高 |
| スタブ生成 | 中 | 高 | 中 |
| コンパイラプラグイン | 高 | 高 | 低 |

## 次のステップ

1. [x] Fennelのコメント出力方法を調査 → `(lua)`で可能
2. [ ] `fn:`マクロのPoC実装
3. [ ] 複雑な型（テーブル、ユニオン）の構文検討
4. [ ] Conjure + lua-language-serverの連携テスト
