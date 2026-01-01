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
- [ ] Hot reload

## Testing

- [ ] sokol.audio bindings
- [ ] sokol.shape bindings
