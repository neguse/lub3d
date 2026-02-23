# Current Status

## Overview

Skip-aware metrics and full module audit completed. All 14 modules show 100% audited coverage (every parsed declaration is either bound or explicitly skipped with reason). No active feature work.

## Active Tasks

None

## Known Issues

- WASM+WebGPU: Fullscreen transition crashes — sokol_app.h creates swapchain texture with size 0 during resize. Needs patch to `_sapp_wgpu_create_swapchain` to guard against zero dimensions. Upstream issue/PR to floooh/sokol pending.
