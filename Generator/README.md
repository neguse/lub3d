# Generator Architecture

Clang AST から Lua バインディング (C/C++ + LuaCATS) を自動生成するパイプライン。

## 構造

```
[入力層]           [中心]              [出力層]
ClangAst.Types ──> BindingType <── CBindingGen (C コード文字列)
TypeRegistry       ModuleSpec    <── LuaCatsGen (LuaCATS 文字列)
                      ^
                  各 Module の
                  BuildSpec()
```

## 設計原則

1. **ModuleSpec / BindingType がアーキテクチャの中心。** 入力層 (ClangAst) と出力層 (CBinding, LuaCats) はこの中心にのみ依存する。互いに直接依存してはならない。

2. **BindingType が唯一の型表現。** ClangAst.Types は入力層の内部型、LuaCats.Type は出力層の内部型。Module 境界を越えるのは BindingType だけ。

3. **Pipeline.cs は文字列ヘルパーに徹する。** `ToPascalCase`, `StripPrefix`, `StripTypeSuffix`, `EnumItemName` など。型変換は行わない。

4. **CBindingGen の公開 API は `Generate(ModuleSpec)` のみ。** 内部メソッドは private。テストは ModuleSpec を組み立てて出力文字列を検証する。

5. **各 Module は「ClangAst → ModuleSpec」の変換器。** TypeRegistry を受け取り ModuleSpec を返す。CBindingGen も LuaCatsGen も知らない。

6. **特殊処理は ModuleSpec のフィールドで表現する。** CBindingGen が特定の型名をハードコードしてチェックするパターンは禁止。Module 側から ModuleSpec のフィールドで宣言する。

## モジュール追加方法

### Sokol 系 (C ヘッダ, prefix ベース)

`SokolModule` を継承し `ModuleName` と `Prefix` をオーバーライドする。必要に応じて `Ignores`, `ShouldGenerateFunc`, `HasMetamethods`, `ExtraCCode` 等のフックを使う。

```csharp
public class Gfx : SokolModule
{
    public override string ModuleName => "sokol.gfx";
    public override string Prefix => "sg_";
}
```

### 独立モジュール (C/C++ ヘッダ)

`IModule` を直接実装する。`BuildSpec` で TypeRegistry から ModuleSpec を構築し、`GenerateC` / `GenerateLua` で生成する。
