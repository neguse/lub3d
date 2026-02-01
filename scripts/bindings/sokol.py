"""
Sokol binding configuration

Configures the binding generator with Sokol-specific customizations:
- sg_range string initialization
- Hot-reload callbacks for sapp_desc
- Direct callbacks for saudio_desc
"""

from binding_gen import (
    Generator, TypeHandler, ConversionContext,
    StructHandler, CallbackConfig,
)


# ==============================================================================
# Custom Type Handlers
# ==============================================================================

class SgRangeHandler(TypeHandler):
    """sg_range: can be initialized from string (binary data)"""

    def lua_to_c(self, ctx: ConversionContext) -> str:
        var = ctx.var
        idx = ctx.idx
        return f'''sg_range {var}_storage;
    const sg_range* {var};
    if (lua_isstring(L, {idx})) {{
        size_t {var}_len;
        const char* {var}_str = lua_tolstring(L, {idx}, &{var}_len);
        {var}_storage.ptr = {var}_str;
        {var}_storage.size = {var}_len;
        {var} = &{var}_storage;
    }} else {{
        {var} = (const sg_range*)luaL_checkudata(L, {idx}, "sokol.Range");
    }}'''

    def c_to_lua(self, ctx: ConversionContext) -> str:
        var = ctx.var
        return f'''sg_range* ud = (sg_range*)lua_newuserdatauv(L, sizeof(sg_range), 0);
    *ud = {var};
    luaL_setmetatable(L, "sokol.Range");'''

    def luacats_type(self) -> str:
        return 'gfx.Range|string'


# ==============================================================================
# Struct Handlers with Callback Configurations
# ==============================================================================

# sapp_desc: hot-reload enabled callbacks
sapp_desc_handler = StructHandler(
    callbacks={
        'init_cb': CallbackConfig(hotreload=True, signature='fun()'),
        'frame_cb': CallbackConfig(hotreload=True, signature='fun()'),
        'cleanup_cb': CallbackConfig(hotreload=True, signature='fun()'),
        'event_cb': CallbackConfig(hotreload=True, signature='fun(ev: app.Event)'),
    },
    validate_keys=True,
)

# saudio_desc: direct reference (no hot-reload needed for audio callback)
saudio_desc_handler = StructHandler(
    callbacks={
        'stream_cb': CallbackConfig(
            hotreload=False,
            signature='fun(buffer: lightuserdata, num_frames: integer, num_channels: integer)',
        ),
    },
)

# slog_logger: logger callback (no hot-reload)
slog_logger_handler = StructHandler(
    callbacks={
        'func': CallbackConfig(hotreload=False, signature='fun(...)'),
    },
    skip_fields=['func'],  # Skip func field (variadic, not supported)
)


# ==============================================================================
# Configuration
# ==============================================================================

def configure(gen: Generator):
    """Configure generator with Sokol-specific settings"""

    # Global ignores
    gen.ignore(
        'sdtx_printf',
        'sdtx_vprintf',
        'sg_install_trace_hooks',
        'sg_trace_hooks',
    )

    # === gfx module ===
    gfx = gen.module('sg_')
    gfx.type_handlers['sg_range'] = SgRangeHandler()

    # === app module ===
    app = gen.module('sapp_')
    app.struct_handlers['sapp_desc'] = sapp_desc_handler

    # === audio module ===
    audio = gen.module('saudio_')
    audio.struct_handlers['saudio_desc'] = saudio_desc_handler

    # === log module ===
    log = gen.module('slog_')
    log.struct_handlers['slog_logger'] = slog_logger_handler
