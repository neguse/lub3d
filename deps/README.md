# Dependencies

Third-party libraries used by Lub3d.

## License Summary

| Library | License | Notes |
|---------|---------|-------|
| lua | MIT | Lua 5.5 |
| sokol | zlib | Graphics/app/audio libraries |
| sokol-tools | MIT | Shader compiler (sokol-shdc) |
| lume | MIT | Lua utilities |
| imgui | MIT | Dear ImGui |
| bc7enc_rdo | MIT/Public Domain | BC7 texture encoder with RDO |

## References

Shader techniques referenced from:

- [3D Game Shaders For Beginners](https://github.com/lettier/3d-game-shaders-for-beginners) - BSD-3-Clause (shader code)

## Generating License Info

```bash
python3 scripts/gen_licenses.py
```

This generates `gen/licenses.c` which is compiled into the binary and accessible via `require("lub3d.licenses")`.
