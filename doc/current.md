# Current Status

## Overview

T06 ownership model research completed. sol3 / WASI 調査結果と Generator 改善設計指針をドキュメント化済み。実装フェーズ (ModuleSpec 変更、CBindingGen 拡張、miniaudio PoC) は設計指針に基づき次ステップとして実行可能。

## Active Tasks

None

## Recent Completions

- T06: Ownership model research — `doc/ownership-research.md` (調査結果) + `doc/ownership-design.md` (設計指針)

## Next Steps

- T06 実装フェーズ: `ownership-design.md` に記載の ModuleSpec 変更を実装
- T07: Jolt Physics binding (T06 ownership model を活用)
- T08: ozz-animation binding

## Known Issues

- WASM+WebGPU: Fullscreen transition crashes — sokol_app.h creates swapchain texture with size 0 during resize. Needs patch to `_sapp_wgpu_create_swapchain` to guard against zero dimensions. Upstream issue/PR to floooh/sokol pending.
