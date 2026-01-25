--- Song Select Screen UI
--- IMGUI-based song selection interface
local imgui = require("imgui")
local const = require("examples.rhythm.const")

-- ImGui constants (not exported by bindings)
local WindowFlags_NoResize = 2
local WindowFlags_NoMove = 4
local WindowFlags_NoCollapse = 32
local ChildFlags_Borders = 1
local Cond_Always = 1

-- Style colors
local Col_Header = 24
local Col_HeaderHovered = 25
local Col_HeaderActive = 26
local Col_FrameBg = 7
local Col_Border = 5

---@class SelectScreen
---@field songs SongEntry[] Available songs
---@field selected_index integer Currently selected song index
---@field scroll_to_selected boolean Flag to scroll to selected item
---@field on_select fun(song: SongEntry)|nil Callback when song is selected for play
local SelectScreen = {}
SelectScreen.__index = SelectScreen

--- Create a new SelectScreen
---@return SelectScreen
function SelectScreen.new()
    local self = setmetatable({}, SelectScreen)
    self.songs = {}
    self.selected_index = 1
    self.scroll_to_selected = false
    self.on_select = nil
    return self
end

--- Set the song list
---@param songs SongEntry[]
function SelectScreen:set_songs(songs)
    self.songs = songs
    self.selected_index = 1
end

--- Move selection up
function SelectScreen:move_up()
    if self.selected_index > 1 then
        self.selected_index = self.selected_index - 1
        self.scroll_to_selected = true
    end
end

--- Move selection down
function SelectScreen:move_down()
    if self.selected_index < #self.songs then
        self.selected_index = self.selected_index + 1
        self.scroll_to_selected = true
    end
end

--- Confirm selection
function SelectScreen:confirm()
    if self.on_select and self.songs[self.selected_index] then
        self.on_select(self.songs[self.selected_index])
    end
end

--- Get currently selected song
---@return SongEntry|nil
function SelectScreen:get_selected()
    return self.songs[self.selected_index]
end

--- Draw the select screen
function SelectScreen:draw()
    local window_flags = WindowFlags_NoResize + WindowFlags_NoMove + WindowFlags_NoCollapse

    -- Style: dark background with visible selection
    imgui.push_style_color_int_vec4(Col_Header, {0.2, 0.4, 0.8, 1.0})         -- Selected
    imgui.push_style_color_int_vec4(Col_HeaderHovered, {0.3, 0.3, 0.5, 1.0})  -- Hovered
    imgui.push_style_color_int_vec4(Col_HeaderActive, {0.2, 0.4, 0.8, 1.0})   -- Active
    imgui.push_style_color_int_vec4(Col_FrameBg, {0.0, 0.0, 0.0, 1.0})        -- Black background
    imgui.push_style_var_int_float(13, 1.0)  -- FrameBorderSize = 1

    -- Full screen window
    imgui.set_next_window_pos({0, 0}, Cond_Always, {0, 0})
    imgui.set_next_window_size({const.SCREEN_WIDTH, const.SCREEN_HEIGHT}, Cond_Always)

    if imgui.begin("Song Select", nil, window_flags) then
        -- Title
        imgui.text_unformatted("Select a song and press ENTER to play")
        imgui.separator()

        -- Song count
        imgui.text_unformatted(string.format("Songs: %d", #self.songs))
        imgui.separator()

        -- Left panel: Song list
        local list_width = const.SCREEN_WIDTH * 0.55
        local list_height = const.SCREEN_HEIGHT - 180

        imgui.begin_child_str_vec2_int_int("SongList", {list_width, list_height}, ChildFlags_Borders, 0)

        for i, song in ipairs(self.songs) do
            -- Use index in ID to avoid conflicts with duplicate titles
            local display_text = string.format("[Lv.%d] %s##%d", song.playlevel, song.title, i)
            local is_selected = (i == self.selected_index)

            -- Scroll to selected item if needed
            if is_selected and self.scroll_to_selected then
                imgui.set_scroll_here_y(0.5)
                self.scroll_to_selected = false
            end

            local clicked = imgui.selectable_str_bool_int_vec2(display_text, is_selected, 0, {0, 0})
            if clicked then
                self.selected_index = i
            end

            -- Double-click to select
            if imgui.is_item_hovered(0) and imgui.is_mouse_double_clicked(0) then
                self.selected_index = i
                self:confirm()
            end
        end

        imgui.end_child()

        -- Right panel: Song details
        imgui.same_line(0, 10)

        local detail_width = const.SCREEN_WIDTH - list_width - 30
        imgui.begin_child_str_vec2_int_int("SongDetail", {detail_width, list_height}, ChildFlags_Borders, 0)

        local song = self.songs[self.selected_index]
        if song then
            imgui.text_unformatted("Title:")
            imgui.text_unformatted(song.title)
            imgui.spacing()

            imgui.text_unformatted("Artist:")
            imgui.text_unformatted(song.artist)
            imgui.spacing()

            if song.genre ~= "" then
                imgui.text_unformatted("Genre:")
                imgui.text_unformatted(song.genre)
                imgui.spacing()
            end

            imgui.separator()

            imgui.text_unformatted(string.format("BPM: %.1f", song.bpm))
            imgui.text_unformatted(string.format("Level: %d", song.playlevel))

            if song.difficulty > 0 then
                local diff_names = {"BEGINNER", "NORMAL", "HYPER", "ANOTHER", "INSANE"}
                local diff_name = diff_names[song.difficulty] or string.format("DIFF %d", song.difficulty)
                imgui.text_unformatted(string.format("Difficulty: %s", diff_name))
            end

            imgui.separator()
            imgui.spacing()

            -- File path (truncated)
            imgui.text_unformatted("Path:")
            local short_path = song.path
            if #short_path > 50 then
                short_path = "..." .. short_path:sub(-47)
            end
            imgui.text_unformatted(short_path)
        else
            imgui.text_unformatted("No song selected")
        end

        imgui.end_child()

        -- Bottom: Instructions
        imgui.separator()
        imgui.text_unformatted("UP/DOWN: Select  |  ENTER: Play  |  ESC: Quit")
    end
    imgui.end_()

    -- Pop styles
    imgui.pop_style_var(1)
    imgui.pop_style_color(4)
end

--- Handle keyboard input
---@param key_code integer
---@return boolean handled
function SelectScreen:handle_key(key_code)
    local app = require("sokol.app")

    if key_code == app.Keycode.UP then
        self:move_up()
        return true
    elseif key_code == app.Keycode.DOWN then
        self:move_down()
        return true
    elseif key_code == app.Keycode.ENTER then
        self:confirm()
        return true
    end

    return false
end

return SelectScreen
