-- mane3d example: 3D Block Breaker
local gfx = require("sokol.gfx")
local app = require("sokol.app")
local glue = require("sokol.glue")
local log = require("lib.log")
local shaderMod = require("lib.shader")
local util = require("lib.util")
local glm = require("lib.glm")

-- Game constants
local FIELD_WIDTH = 10
local FIELD_HEIGHT = 12
local BLOCK_ROWS = 5
local BLOCK_COLS = 8
local BLOCK_WIDTH = 1.0
local BLOCK_HEIGHT = 0.4
local BLOCK_DEPTH = 0.5
local PADDLE_WIDTH = 2.0
local PADDLE_HEIGHT = 0.3
local PADDLE_DEPTH = 0.5
local BALL_SIZE = 0.3

-- Game state
local paddle_x = 0
local ball_x, ball_y = 0, -4
local ball_vx, ball_vy = 2.5, 3.5
local blocks = {}
local game_over = false
local score = 0
local t = 0
local keys_down = {}

-- Graphics resources
---@type gfx.Shader?
local shader = nil
---@type gfx.Pipeline?
local pipeline = nil
---@type gfx.Buffer?
local vbuf = nil
---@type gfx.Buffer?
local ibuf = nil

-- Shader with MVP matrix and color uniform
local shader_source = [[
@vs vs
in vec3 pos;
in vec3 normal;

out vec3 v_normal;
out vec3 v_world_pos;
out vec4 v_color;

layout(binding=0) uniform vs_params {
    mat4 mvp;
    mat4 model;
    vec4 color;
};

void main() {
    gl_Position = mvp * vec4(pos, 1.0);
    v_normal = normalize(mat3(model) * normal);
    v_world_pos = (model * vec4(pos, 1.0)).xyz;
    v_color = color;
}
@end

@fs fs
in vec3 v_normal;
in vec3 v_world_pos;
in vec4 v_color;

out vec4 frag_color;

void main() {
    vec3 light_pos = vec3(5.0, 10.0, 15.0);
    vec3 view_pos = vec3(0.0, -5.0, 18.0);

    vec3 light_dir = normalize(light_pos - v_world_pos);
    vec3 view_dir = normalize(view_pos - v_world_pos);
    vec3 n = normalize(v_normal);

    // Ambient
    float ambient = 0.25;

    // Diffuse
    float diff = max(dot(n, light_dir), 0.0);

    // Specular (Blinn-Phong)
    vec3 halfway = normalize(light_dir + view_dir);
    float spec = pow(max(dot(n, halfway), 0.0), 32.0);

    vec3 result = v_color.rgb * (ambient + diff * 0.7) + vec3(1.0) * spec * 0.3;
    frag_color = vec4(result, 1.0);
}
@end

@program breakout vs fs
]]

-- Generate cube vertices (pos, normal) - no color, color comes from uniform
local function make_cube_vertices()
    local v = {}
    local faces = {
        -- front (z+)
        {{ -0.5, -0.5,  0.5}, { 0.5, -0.5,  0.5}, { 0.5,  0.5,  0.5}, {-0.5,  0.5,  0.5}, {0, 0, 1}},
        -- back (z-)
        {{ 0.5, -0.5, -0.5}, {-0.5, -0.5, -0.5}, {-0.5,  0.5, -0.5}, { 0.5,  0.5, -0.5}, {0, 0, -1}},
        -- top (y+)
        {{-0.5,  0.5,  0.5}, { 0.5,  0.5,  0.5}, { 0.5,  0.5, -0.5}, {-0.5,  0.5, -0.5}, {0, 1, 0}},
        -- bottom (y-)
        {{-0.5, -0.5, -0.5}, { 0.5, -0.5, -0.5}, { 0.5, -0.5,  0.5}, {-0.5, -0.5,  0.5}, {0, -1, 0}},
        -- right (x+)
        {{ 0.5, -0.5,  0.5}, { 0.5, -0.5, -0.5}, { 0.5,  0.5, -0.5}, { 0.5,  0.5,  0.5}, {1, 0, 0}},
        -- left (x-)
        {{-0.5, -0.5, -0.5}, {-0.5, -0.5,  0.5}, {-0.5,  0.5,  0.5}, {-0.5,  0.5, -0.5}, {-1, 0, 0}},
    }

    for _, face in ipairs(faces) do
        local n = face[5]
        for i = 1, 4 do
            local p = face[i]
            -- pos
            table.insert(v, p[1])
            table.insert(v, p[2])
            table.insert(v, p[3])
            -- normal
            table.insert(v, n[1])
            table.insert(v, n[2])
            table.insert(v, n[3])
        end
    end
    return v
end

local function make_cube_indices()
    local indices = {}
    for face = 0, 5 do
        local base = face * 4
        table.insert(indices, base + 0)
        table.insert(indices, base + 1)
        table.insert(indices, base + 2)
        table.insert(indices, base + 0)
        table.insert(indices, base + 2)
        table.insert(indices, base + 3)
    end
    return indices
end

local function pack_indices(indices)
    return string.pack(string.rep("H", #indices), table.unpack(indices))
end

local function init_blocks()
    blocks = {}
    local colors = {
        glm.vec3(1.0, 0.3, 0.3),  -- red
        glm.vec3(1.0, 0.6, 0.2),  -- orange
        glm.vec3(1.0, 1.0, 0.3),  -- yellow
        glm.vec3(0.3, 1.0, 0.3),  -- green
        glm.vec3(0.3, 0.6, 1.0),  -- blue
    }
    for row = 1, BLOCK_ROWS do
        for col = 1, BLOCK_COLS do
            local x = (col - (BLOCK_COLS + 1) / 2) * (BLOCK_WIDTH + 0.1)
            local y = FIELD_HEIGHT / 2 - row * (BLOCK_HEIGHT + 0.1) - 1
            table.insert(blocks, {
                x = x,
                y = y,
                alive = true,
                color = colors[row]
            })
        end
    end
end

function init()
    log.info("3D Block Breaker starting...")

    -- Compile shader with uniform block (2 mat4 + 1 vec4 = 144 bytes)
    shader = shaderMod.compile(shader_source, "breakout", {
        {
            stage = gfx.ShaderStage.VERTEX,
            size = 144,
            glsl_uniforms = {
                { type = gfx.UniformType.MAT4, glsl_name = "mvp" },
                { type = gfx.UniformType.MAT4, glsl_name = "model" },
                { type = gfx.UniformType.FLOAT4, glsl_name = "color" },
            }
        }
    }, {
        -- D3D11 vertex attribute semantics: pos, normal
        { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 0 },
        { hlsl_sem_name = "TEXCOORD", hlsl_sem_index = 1 },
    })
    if not shader then
        log.error("Shader compilation failed!")
        return
    end

    pipeline = gfx.make_pipeline(gfx.PipelineDesc({
        shader = shader,
        layout = {
            attrs = {
                { format = gfx.VertexFormat.FLOAT3 },  -- pos
                { format = gfx.VertexFormat.FLOAT3 },  -- normal
            }
        },
        index_type = gfx.IndexType.UINT16,
        cull_mode = gfx.CullMode.BACK,
        depth = {
            compare = gfx.CompareFunc.LESS_EQUAL,
            write_enabled = true,
        },
        primitive_type = gfx.PrimitiveType.TRIANGLES,
    }))

    if gfx.query_pipeline_state(pipeline) ~= gfx.ResourceState.VALID then
        log.error("Pipeline creation failed!")
        return
    end

    -- Create static cube vertex buffer (6 faces * 4 vertices * 6 floats = 144 floats)
    local vertices = make_cube_vertices()
    vbuf = gfx.make_buffer(gfx.BufferDesc({
        data = gfx.Range(util.pack_floats(vertices))
    }))

    local indices = make_cube_indices()
    ibuf = gfx.make_buffer(gfx.BufferDesc({
        usage = { index_buffer = true },
        data = gfx.Range(pack_indices(indices))
    }))

    init_blocks()
    log.info(string.format("Game initialized with %d blocks", #blocks))
end

local function update_game(dt)
    if game_over then return end

    -- Update ball position
    ball_x = ball_x + ball_vx * dt
    ball_y = ball_y + ball_vy * dt

    -- Wall collision (left/right)
    if ball_x < -FIELD_WIDTH/2 + BALL_SIZE/2 then
        ball_x = -FIELD_WIDTH/2 + BALL_SIZE/2
        ball_vx = -ball_vx
    elseif ball_x > FIELD_WIDTH/2 - BALL_SIZE/2 then
        ball_x = FIELD_WIDTH/2 - BALL_SIZE/2
        ball_vx = -ball_vx
    end

    -- Wall collision (top)
    if ball_y > FIELD_HEIGHT/2 - BALL_SIZE/2 then
        ball_y = FIELD_HEIGHT/2 - BALL_SIZE/2
        ball_vy = -ball_vy
    end

    -- Ball out of bounds (bottom)
    if ball_y < -FIELD_HEIGHT/2 then
        game_over = true
        log.info("Game Over! Score: " .. score)
        return
    end

    -- Paddle collision
    local paddle_top = -FIELD_HEIGHT/2 + 1 + PADDLE_HEIGHT/2
    local paddle_bottom = -FIELD_HEIGHT/2 + 1 - PADDLE_HEIGHT/2
    if ball_vy < 0 and
       ball_y - BALL_SIZE/2 < paddle_top and
       ball_y + BALL_SIZE/2 > paddle_bottom and
       ball_x > paddle_x - PADDLE_WIDTH/2 and
       ball_x < paddle_x + PADDLE_WIDTH/2 then
        ball_y = paddle_top + BALL_SIZE/2
        ball_vy = -ball_vy
        -- Add angle based on where ball hit paddle
        local hit_pos = (ball_x - paddle_x) / (PADDLE_WIDTH/2)
        ball_vx = ball_vx + hit_pos * 2
        -- Clamp velocity
        ball_vx = glm.clamp(ball_vx, -6, 6)
    end

    -- Block collision
    for _, block in ipairs(blocks) do
        if block.alive then
            local bx, by = block.x, block.y
            local hw, hh = BLOCK_WIDTH/2, BLOCK_HEIGHT/2
            if ball_x + BALL_SIZE/2 > bx - hw and
               ball_x - BALL_SIZE/2 < bx + hw and
               ball_y + BALL_SIZE/2 > by - hh and
               ball_y - BALL_SIZE/2 < by + hh then
                block.alive = false
                score = score + 10

                -- Determine collision side
                local dx = ball_x - bx
                local dy = ball_y - by
                if math.abs(dx) / hw > math.abs(dy) / hh then
                    ball_vx = -ball_vx
                else
                    ball_vy = -ball_vy
                end
                break
            end
        end
    end

    -- Check win condition
    local all_dead = true
    for _, block in ipairs(blocks) do
        if block.alive then all_dead = false break end
    end
    if all_dead then
        log.info("You Win! Score: " .. score)
        init_blocks()
        ball_x, ball_y = 0, -4
        ball_vx, ball_vy = 2.5, 3.5
    end
end

-- Pack mat4 + mat4 + vec4 as uniforms
local function pack_uniforms(mvp, model, color)
    local data = {}
    for i = 1, 16 do data[i] = mvp[i] end
    for i = 1, 16 do data[16 + i] = model[i] end
    data[33] = color.x
    data[34] = color.y
    data[35] = color.z
    data[36] = 1.0
    return util.pack_floats(data)
end

local function draw_cube(proj, view, pos, scale, color)
    local model = glm.translate(pos) * glm.scale(scale)
    local mvp = proj * view * model

    gfx.apply_uniforms(0, gfx.Range(pack_uniforms(mvp, model, color)))
    gfx.draw(0, 36, 1)
end

function frame()
    t = t + 1.0 / 60.0
    local dt = 1.0 / 60.0

    if not pipeline or not vbuf or not ibuf then return end

    -- Paddle movement
    local paddle_speed = 8.0 * dt
    if keys_down[app.Keycode.LEFT] or keys_down[app.Keycode.A] then
        paddle_x = paddle_x - paddle_speed
    end
    if keys_down[app.Keycode.RIGHT] or keys_down[app.Keycode.D] then
        paddle_x = paddle_x + paddle_speed
    end
    -- Clamp paddle
    local max_x = FIELD_WIDTH/2 - PADDLE_WIDTH/2
    paddle_x = glm.clamp(paddle_x, -max_x, max_x)

    update_game(dt)

    -- Camera setup
    local aspect = app.widthf() / app.heightf()
    local proj = glm.perspective(glm.radians(45), aspect, 0.1, 100.0)
    local view = glm.lookat(
        glm.vec3(0, -5, 18),
        glm.vec3(0, 0, 0),
        glm.vec3(0, 1, 0)
    )

    -- Begin render pass
    gfx.begin_pass(gfx.Pass({
        action = gfx.PassAction({
            colors = { {
                load_action = gfx.LoadAction.CLEAR,
                clear_value = { r = 0.1, g = 0.1, b = 0.15, a = 1.0 }
            } },
            depth = {
                load_action = gfx.LoadAction.CLEAR,
                clear_value = 1.0
            }
        }),
        swapchain = glue.swapchain()
    }))

    gfx.apply_pipeline(pipeline)
    gfx.apply_bindings(gfx.Bindings({
        vertex_buffers = { vbuf },
        index_buffer = ibuf
    }))

    -- Draw walls (faint)
    local wall_color = glm.vec3(0.2, 0.2, 0.3)
    draw_cube(proj, view, glm.vec3(-FIELD_WIDTH/2 - 0.25, 0, 0), glm.vec3(0.5, FIELD_HEIGHT, 1), wall_color)
    draw_cube(proj, view, glm.vec3(FIELD_WIDTH/2 + 0.25, 0, 0), glm.vec3(0.5, FIELD_HEIGHT, 1), wall_color)
    draw_cube(proj, view, glm.vec3(0, FIELD_HEIGHT/2 + 0.25, 0), glm.vec3(FIELD_WIDTH + 1, 0.5, 1), wall_color)

    -- Draw paddle
    local paddle_y = -FIELD_HEIGHT/2 + 1
    draw_cube(proj, view, glm.vec3(paddle_x, paddle_y, 0), glm.vec3(PADDLE_WIDTH, PADDLE_HEIGHT, PADDLE_DEPTH), glm.vec3(0.8, 0.8, 0.9))

    -- Draw ball
    local pulse = math.sin(t * 10) * 0.1 + 0.9
    draw_cube(proj, view, glm.vec3(ball_x, ball_y, 0), glm.vec3(BALL_SIZE, BALL_SIZE, BALL_SIZE), glm.vec3(pulse, pulse, 1.0))

    -- Draw blocks
    for _, block in ipairs(blocks) do
        if block.alive then
            draw_cube(proj, view, glm.vec3(block.x, block.y, 0), glm.vec3(BLOCK_WIDTH, BLOCK_HEIGHT, BLOCK_DEPTH), block.color)
        end
    end

    gfx.end_pass()
    gfx.commit()
end

function cleanup()
end

function event(ev)
    if ev.type == app.EventType.KEY_DOWN then
        keys_down[ev.key_code] = true
        if ev.key_code == app.Keycode.Q then
            app.quit()
        end
        if ev.key_code == app.Keycode.R then
            -- Reset game
            game_over = false
            score = 0
            ball_x, ball_y = 0, -4
            ball_vx, ball_vy = 2.5, 3.5
            paddle_x = 0
            init_blocks()
            log.info("Game reset!")
        end
    elseif ev.type == app.EventType.KEY_UP then
        keys_down[ev.key_code] = false
    end
end
