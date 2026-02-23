# Current Status

## Overview

T10 lubs check 警告修正完了。T06 research + T10 lint cleanup が終わり、次は T06-impl (Generator ownership 抽象の実装) へ。

## Active Tasks

None

## Recent Completions

- T10: lubs check 警告の修正 (60件) — `.luarc.json` naming rule 拡張 + 28 Lua files 修正
- T06: Ownership model research — `doc/ownership-research.md` + `doc/ownership-design.md`

## Next Steps

- T06-impl: Generator ownership 抽象の実装 (DependencyBinding, destroy 自動生成)
- T07: Jolt Physics binding
- T08: ozz-animation binding

## Known Issues

- WASM+WebGPU: Fullscreen transition crashes — sokol_app.h creates swapchain texture with size 0 during resize. Needs patch to `_sapp_wgpu_create_swapchain` to guard against zero dimensions. Upstream issue/PR to floooh/sokol pending.
