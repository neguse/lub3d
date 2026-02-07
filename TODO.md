# TODO

## Known Issues

- [ ] WASM+WebGPU: Fullscreen transition crashes
  - Cause: sokol_app.h creates swapchain texture with size 0 during resize
  - Fix: Patch `_sapp_wgpu_create_swapchain` to guard against zero dimensions
  - Upstream: Need to file issue/PR to floooh/sokol

## Documentation

- [x] Update README: WebGPU now works (WASM)
- [ ] Update README: Add sokol.audio, sokol.shape to module list

## Ideas (from README)

### Retained Mode + Auto GC

- [ ] Pass all resources every frame, same handle = reuse
- [ ] Unused handles get garbage collected

### Blender as Editor

- [ ] Object name = script name (`elevator_01` -> `elevator_01.lua`)
- [ ] Custom properties for parameters
- [ ] glTF export/import

### Other

- [ ] Fennel + sequence macros
- [x] Hot reload (lib/hotreload.lua + lume.hotswap)
- [x] Render pipeline with error recovery (lib/render_pipeline.lua)
- [x] GC-safe GPU resource wrappers (lib/gpu.lua)

## 3D Game Shaders Tutorial (lettier/3d-game-shaders-for-beginners)

Step-by-step port to lub3d.

### Setup

- [x] Assets: egg + textures in `assets/3d-shaders/` (gitignored)
- [x] egg2lua.py: Convert EGG to Lua table format (scripts/egg2lua.py)

### Tutorial Sections

- [x] 4.  Reference Frames (mat4/mat3 inverse, transpose, normalMatrix in glm.lua)
- [x] 5.  GLSL (sokol-shdc compatibility - covered)
- [x] 6.  Render To Texture (conceptual understanding)
- [x] 7.  Texturing (stb_image + util.load_texture)
- [x] 8.  Lighting (examples/lighting.lua - Phong/Blinn-Phong) ✓ working
- [x] 9.  Blinn-Phong (included in lighting.lua) ✓ working
- [x] 10. Fresnel Factor (Schlick's approximation on specular)
- [x] 11. Rim Lighting (edge glow effect)
- [x] 12. Cel Shading (toon bands + hard specular)
- [x] 13. Normal Mapping (examples/model.lua + mill-scene)
- [x] 14. Deferred Rendering (examples/deferred.lua + G-buffer MRT)
- [x] 15. Fog (gradient sky, sun position, gamma-corrected colors)
- [x] 16. Blur (box blur post-processing)
- [x] 17. Bloom (brightness threshold + blur)
- [x] 18. SSAO (view-space hemisphere sampling)
- [x] 19. Motion Blur (previous/current view matrix comparison)
- [x] 20. Chromatic Aberration (radial RGB offset)
- [x] 21. Screen Space Reflection (ray marching + hole-fill blur)
- [ ] 22. Screen Space Refraction
- [ ] 23. Foam
- [ ] 24. Flow Mapping
- [ ] 25. Outlining
- [ ] 26. Depth Of Field
- [ ] 27. Posterization
- [ ] 28. Pixelization
- [ ] 29. Sharpen
- [ ] 30. Dilation
- [ ] 31. Film Grain
- [ ] 32. Lookup Table (LUT)
- [ ] 33. Gamma Correction

## Testing

- [ ] sokol.audio bindings
- [ ] sokol.shape bindings
