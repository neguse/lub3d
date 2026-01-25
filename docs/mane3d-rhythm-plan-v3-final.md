# mane3d-rhythm 開発計画 v3

## 概要

mane3dエンジンをベースとした汎用リズムゲームプレイヤー/フレームワーク。

### ビジョン

1. **プレイヤーとして便利**: BMS/StepMania/osu!等の譜面をドロップして即プレイ
2. **カスタマイズ可能**: スキン、判定、ゲージを自由に設定
3. **拡張可能**: Luaで機能追加、独自ゲームモード作成
4. **ライブラリとして利用可能**: コア部分を切り出して別ゲーム開発に使用

---

## 設計原則（v2で追加）

### 時間軸の統一

| 項目 | 単位 | 用途 |
|------|------|------|
| **tick** | 整数 (1小節=9600tick) | ノーツ位置、譜面データの正規軸 |
| **beat** | float (1小節=4.0beat) | tick から派生、表示計算用 |
| **time_us** | int64 マイクロ秒 | 判定、オーディオ発音タイミング |

- **Core内部は全て `time_us` (マイクロ秒整数)**
- **譜面データは `tick` を正規軸**とし、`time_us` は TimingMap から導出
- 表示用の ms 変換は最終段のみ

### TimingMap が全ての中心

```
┌─────────────┐
│ UniversalChart │
│  notes: tick   │
│  timing: tick  │
└───────┬───────┘
        │
        ▼
┌─────────────┐
│  TimingMap    │  ← Core の心臓
│  tick ↔ time  │
│  (双方向変換)  │
└───────┬───────┘
        │
   ┌────┴────┐
   ▼         ▼
┌──────┐  ┌──────┐
│ Judge │  │Render│
│time_us│  │ beat │
└──────┘  └──────┘
```

---

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│                    mane3d-rhythm Player                     │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐           │
│  │  選曲画面   │ │  プレイ画面 │ │ リザルト画面│  ...      │
│  └─────────────┘ └─────────────┘ └─────────────┘           │
│                         ↑ Lua スキン/シーン                 │
├─────────────────────────────────────────────────────────────┤
│                    mane3d-rhythm Core                       │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐       │
│  │  Loader  │ │TimingMap │ │  Judge   │ │Conductor │       │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘       │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐       │
│  │  Chart   │ │ Scoring  │ │  Gauge   │ │  Replay  │       │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘       │
├─────────────────────────────────────────────────────────────┤
│                      mane3d Engine                          │
│         (Lua 5.5 + Sokol + WebGPU + Hot Reload)            │
└─────────────────────────────────────────────────────────────┘
```

### レイヤ責務（明確化）

| レイヤ | 責務 | 決定論的 |
|--------|------|----------|
| **Core** | フォーマット読込→UniversalChart変換、TimingMap、判定ロジック、スコア・ゲージ計算、リプレイ記録再生、乱数管理 | ✅ Yes |
| **Player** | シーン遷移、UI、スキン描画、入力デバイス→Coreへのイベント供給、オーディオI/O（タイミングはCoreが決定） | ❌ No |
| **Engine** | レンダラ、オーディオ出力、ファイルI/O、Lua VM、ホットリロード | ❌ No |

**Coreが決定論的** = 同じ入力なら同じ出力 = リプレイ再現可能

---

## データ構造

### 基本型定義

```lua
-- 時間単位
---@alias Tick integer      -- 譜面位置 (1小節=7680)
---@alias TimeUS integer    -- マイクロ秒 (int64)
---@alias Beat number       -- 拍 (1小節=4.0)

-- ID
---@alias SoundID integer   -- 0-1295 (base36: 00-ZZ)
---@alias ImageID integer   -- 0-1295

-- 定数
-- 解像度は 192 で割り切れる値を選択（BMS STOP精度のため）
-- 7680 / 4 = 1920, 1920 / 192 = 10 → 1/192拍 = 10tick
TICKS_PER_MEASURE = 7680
TICKS_PER_BEAT = 1920
TICKS_PER_192 = 10  -- 1/192拍 = 10tick (BMS STOP単位)
```

### Base36 ID変換

```lua
local BASE36 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

function base36_to_int(s)
    -- "00" -> 0, "0A" -> 10, "ZZ" -> 1295
    s = s:upper()
    local hi = BASE36:find(s:sub(1,1)) - 1
    local lo = BASE36:find(s:sub(2,2)) - 1
    return hi * 36 + lo
end

function int_to_base36(n)
    local hi = math.floor(n / 36)
    local lo = n % 36
    return BASE36:sub(hi+1, hi+1) .. BASE36:sub(lo+1, lo+1)
end
```

### TimingMap（Coreの心臓）

#### 設計原則（STOP境界の定義）

```
【tick_to_time の定義】
tick_to_time(t) は「tick t に到達した瞬間の最小時刻」を返す。

STOPはその tick に到達してから時間が進むので：
- tick_to_time(stop_tick) = STOP開始時刻（STOP分は足さない）
- time_to_tick(stop中の時刻) = stop_tick（tick は進まない）

【セグメント境界の扱い】
- BPMセグメント: [start_tick, end_tick) を担当
- STOPセグメント: start_tick == end_tick（tick は進まず time だけ進む）
- 検索は「tickを含むセグメント」で、STOPは tick_to_time では通過扱い
```

```lua
---@class TimingSegment
---@field start_tick Tick
---@field start_time_us TimeUS
---@field end_tick Tick
---@field end_time_us TimeUS
---@field type "bpm" | "stop"
---@field bpm number?              -- type="bpm" のとき
---@field stop_duration_us TimeUS? -- type="stop" のとき

---@class TimingMap
TimingMap = {}
TimingMap.__index = TimingMap

function TimingMap:new()
    return setmetatable({
        segments = {},  -- TimingSegment[] (tick順ソート済み)
    }, self)
end

-- tick → time_us 変換
-- 【定義】tick t に到達した瞬間の最小時刻を返す
function TimingMap:tick_to_time(tick)
    local seg = self:find_segment_for_tick(tick)
    if not seg then
        return 0
    end
    
    if seg.type == "stop" then
        -- STOPセグメントの場合：
        -- tick == stop_tick なら STOP開始時刻を返す（STOP分は足さない）
        return seg.start_time_us
    end
    
    -- BPM区間: 線形補間
    local tick_delta = tick - seg.start_tick
    local us_per_tick = 60000000 / (seg.bpm * TICKS_PER_BEAT)
    return seg.start_time_us + math.floor(tick_delta * us_per_tick)
end

-- time_us → tick 変換（描画用）
-- 【定義】time_us 時点での譜面位置を返す
function TimingMap:time_to_tick(time_us)
    local seg = self:find_segment_for_time(time_us)
    if not seg then
        return 0
    end
    
    if seg.type == "stop" then
        -- STOP中は tick が進まない
        return seg.start_tick
    end
    
    local time_delta = time_us - seg.start_time_us
    local us_per_tick = 60000000 / (seg.bpm * TICKS_PER_BEAT)
    return seg.start_tick + math.floor(time_delta / us_per_tick)
end

-- tick → beat 変換（表示用）
function TimingMap:tick_to_beat(tick)
    return tick / TICKS_PER_BEAT
end

-- tick でセグメント検索
-- BPMセグメント: start_tick <= tick < end_tick を含むものを返す
-- STOPセグメント: tick_to_time では「通過」扱い（BPMセグメントを優先）
function TimingMap:find_segment_for_tick(tick)
    local result = nil
    
    for _, seg in ipairs(self.segments) do
        if seg.type == "bpm" then
            if seg.start_tick <= tick and tick < seg.end_tick then
                return seg
            end
            if seg.start_tick <= tick then
                result = seg  -- 候補として保持
            end
        end
        -- STOPは tick_to_time では飛ばす（time だけ進むため）
    end
    
    return result
end

-- time でセグメント検索
-- start_time_us <= time_us < end_time_us を満たすセグメントを返す
function TimingMap:find_segment_for_time(time_us)
    for _, seg in ipairs(self.segments) do
        if seg.start_time_us <= time_us and time_us < seg.end_time_us then
            return seg
        end
    end
    
    -- 末尾を超えた場合は最後のセグメント
    if #self.segments > 0 then
        return self.segments[#self.segments]
    end
    
    return nil
end

-- 総時間を取得
function TimingMap:get_total_time_us()
    if #self.segments == 0 then
        return 0
    end
    return self.segments[#self.segments].end_time_us
end
```

### TimingMap構築（end_tick 必須）

```lua
---@param initial_bpm number 初期BPM
---@param timing_events table[] タイミングイベント配列
---@param end_tick Tick 譜面終了tick（必須）
---@return TimingMap
function TimingMap.build(initial_bpm, timing_events, end_tick)
    assert(end_tick, "end_tick is required")
    assert(initial_bpm > 0, "initial_bpm must be positive")
    
    local map = TimingMap:new()
    local current_tick = 0
    local current_time_us = 0
    local current_bpm = initial_bpm
    
    -- イベントを tick 順にソート
    table.sort(timing_events, function(a, b) return a.tick < b.tick end)
    
    for _, event in ipairs(timing_events) do
        -- 現在位置から event.tick までのBPMセグメントを追加
        if event.tick > current_tick then
            local us_per_tick = 60000000 / (current_bpm * TICKS_PER_BEAT)
            local duration_ticks = event.tick - current_tick
            local duration_us = math.floor(duration_ticks * us_per_tick)
            
            table.insert(map.segments, {
                start_tick = current_tick,
                start_time_us = current_time_us,
                end_tick = event.tick,
                end_time_us = current_time_us + duration_us,
                type = "bpm",
                bpm = current_bpm,
            })
            
            current_tick = event.tick
            current_time_us = current_time_us + duration_us
        end
        
        if event.type == "bpm" then
            current_bpm = event.value
            
        elseif event.type == "stop" then
            -- STOP: tick は進まず time だけ進む
            -- event.value は stop_duration_us（直接us指定）
            local stop_duration_us = event.value
            
            table.insert(map.segments, {
                start_tick = current_tick,
                start_time_us = current_time_us,
                end_tick = current_tick,  -- tick は進まない
                end_time_us = current_time_us + stop_duration_us,
                type = "stop",
                stop_duration_us = stop_duration_us,
            })
            
            current_time_us = current_time_us + stop_duration_us
        end
    end
    
    -- 【必須】末尾セグメント（最後のイベント〜end_tick）
    if current_tick < end_tick then
        local us_per_tick = 60000000 / (current_bpm * TICKS_PER_BEAT)
        local duration_ticks = end_tick - current_tick
        local duration_us = math.floor(duration_ticks * us_per_tick)
        
        table.insert(map.segments, {
            start_tick = current_tick,
            start_time_us = current_time_us,
            end_tick = end_tick,
            end_time_us = current_time_us + duration_us,
            type = "bpm",
            bpm = current_bpm,
        })
    end
    
    return map
end
```

### UniversalChart（統一中間表現）

```lua
---@class UniversalChart
UniversalChart = {}
UniversalChart.__index = UniversalChart

function UniversalChart:new()
    return setmetatable({
        -- メタデータ
        meta = {
            format_source = "bms",
            title = "",
            subtitle = "",
            artist = "",
            subartist = "",
            genre = "",
            source_meta = {},
        },
        
        -- 難易度
        difficulty = {
            name = "HYPER",
            level = 10,
            level_system = "bms",
        },
        
        -- ゲームモード
        mode = {
            type = "key",
            lanes = 7,
            scratch = true,
            layout = "iidx_sp",
        },
        
        -- タイミング
        timing = {
            initial_bpm = 150.0,
            events = {},            -- { tick, type, value }[]
            measure_scales = {},    -- [measure] = scale
            offset_us = 0,          -- 譜面由来オフセット（SMのOFFSETなど）
        },
        
        -- スコア計算パラメータ
        scoring = {
            total = 300,
            rank = 2,
        },
        
        -- ノーツ (tick順ソート済み)
        notes = {},
        
        -- BGM (tick順ソート済み)
        bgm = {},
        
        -- サウンドリソース
        sounds = {
            keysounds = {},
            music_file = nil,
        },
        
        -- BGA
        bga = {
            events = {},
            images = {},
        },
        
        -- 小節線 (tick順ソート済み)
        measures = {},
        
        -- 統計
        stats = {
            total_notes = 0,
            total_long_notes = 0,
            total_mines = 0,
            total_measures = 0,
            duration_us = 0,
            last_tick = 0,
        },
        
        -- TimingMap (build_timing で生成)
        timing_map = nil,
        
    }, self)
end

-- last_tick を計算
function UniversalChart:compute_last_tick()
    local last = 0
    
    for _, note in ipairs(self.notes) do
        local note_end = note.end_tick or note.tick
        last = math.max(last, note_end)
    end
    
    for _, bgm in ipairs(self.bgm) do
        last = math.max(last, bgm.tick)
    end
    
    for _, measure in ipairs(self.measures) do
        last = math.max(last, measure.tick)
    end
    
    -- マージン追加（1小節分）
    self.stats.last_tick = last + TICKS_PER_MEASURE
    
    return self.stats.last_tick
end

-- 統計計算
function UniversalChart:compute_stats()
    local stats = self.stats
    
    stats.total_notes = 0
    stats.total_long_notes = 0
    stats.total_mines = 0
    
    for _, note in ipairs(self.notes) do
        if note.type == "normal" then
            stats.total_notes = stats.total_notes + 1
        elseif note.type == "long" then
            stats.total_notes = stats.total_notes + 1
            stats.total_long_notes = stats.total_long_notes + 1
        elseif note.type == "mine" then
            stats.total_mines = stats.total_mines + 1
        end
    end
    
    stats.total_measures = #self.measures
end

-- TimingMap構築とtime_us導出
function UniversalChart:build_timing()
    -- 先に last_tick を計算
    local end_tick = self:compute_last_tick()
    
    -- 統計計算
    self:compute_stats()
    
    -- TimingMap 構築（end_tick 必須）
    self.timing_map = TimingMap.build(
        self.timing.initial_bpm,
        self.timing.events,
        end_tick
    )
    
    -- ノーツの time_us を埋める
    for _, note in ipairs(self.notes) do
        note.time_us = self.timing_map:tick_to_time(note.tick)
        if note.end_tick then
            note.end_time_us = self.timing_map:tick_to_time(note.end_tick)
        end
    end
    
    -- BGMの time_us を埋める
    for _, bgm in ipairs(self.bgm) do
        bgm.time_us = self.timing_map:tick_to_time(bgm.tick)
    end
    
    -- 小節線の time_us を埋める
    for _, measure in ipairs(self.measures) do
        measure.time_us = self.timing_map:tick_to_time(measure.tick)
    end
    
    -- 総時間を統計に反映
    self.stats.duration_us = self.timing_map:get_total_time_us()
end
```

---

## フェーズ1: 最小BMSプレイヤー

### 目標
- BMSファイルを読み込んで最後まで演奏できる
- キー音が正しく再生される
- ノーツが流れてきて押せる（判定なし）

### 1.1 BMSパーサー

#### 対応コマンド (Phase 1)

```
[必須]
#PLAYER n           プレイヤー数 (1/2/3)
#TITLE string       タイトル
#ARTIST string      アーティスト
#BPM n              初期BPM
#WAVxx filename     音声ファイル定義 (xx = base36)
#BMPxx filename     画像ファイル定義 (無視するが読む)
#BPMxx n            拡張BPM定義
#STOPxx n           STOP定義 (1/192拍単位)
#TOTAL n            ゲージ増加量
#RANK n             判定ランク

[チャンネル]
#xxx01:data         BGMチャンネル
#xxx02:data         小節長変更 (特別扱い: 数値)
#xxx03:data         BPM変更 (1-255整数、16進)
#xxx08:data         BPM変更 (拡張、#BPMxx参照)
#xxx09:data         STOP (#STOPxx参照)
#xxx11-19:data      1P可視ノーツ
#xxx21-29:data      2P可視ノーツ (読むが1P相当にマップ)

[Phase 1では無視]
#xxx51-59:data      1Pロングノーツ → Phase 2
#xxx61-69:data      2Pロングノーツ → Phase 2
#LNTYPE / #LNOBJ   → Phase 2
#RANDOM / #IF      → Phase 3
#BMPxx / BGA系     → Phase 4+
```

#### パーサー実装

```lua
BmsParser = {}

function BmsParser:parse(source, options)
    options = options or {}
    
    -- 1. 文字コード検出・変換
    local text = self:convert_encoding(source)
    
    -- 2. 行分割
    local lines = self:split_lines(text)
    
    -- 3. ヘッダ部パース
    local headers = self:parse_headers(lines)
    
    -- 4. チャンネル部パース
    local channels, warnings = self:parse_channels(lines)
    
    -- 5. UniversalChart構築
    local chart = self:build_chart(headers, channels)
    
    -- 6. TimingMap構築とtime_us導出
    chart:build_timing()
    
    return chart, warnings
end

function BmsParser:convert_encoding(source)
    -- Shift_JIS / UTF-8 / EUC-JP 自動判定
    -- 失敗時は Shift_JIS として強制変換、壊れた文字は ? に置換
    
    -- encoding_rs 相当のライブラリを使用
    local encoding = detect_encoding(source)
    return convert_to_utf8(source, encoding, {
        replacement = "?"
    })
end

function BmsParser:parse_headers(lines)
    local headers = {
        player = 1,
        title = "",
        subtitle = "",
        artist = "",
        subartist = "",
        genre = "",
        bpm = 130.0,
        total = 300,
        rank = 2,
        
        -- 定義テーブル
        wav = {},       -- [SoundID] = path
        bmp = {},       -- [ImageID] = path
        bpm_table = {}, -- [SoundID] = bpm値
        stop_table = {}, -- [SoundID] = stop値 (1/192拍単位)
    }
    
    for _, line in ipairs(lines) do
        -- #COMMAND VALUE または #COMMANDxx VALUE
        local cmd, arg = line:match("^#([%w]+)%s+(.+)$")
        if not cmd then
            cmd, arg = line:match("^#([%w]+):(.+)$")
        end
        if not cmd then goto continue end
        
        cmd = cmd:upper()
        
        if cmd == "PLAYER" then
            headers.player = tonumber(arg) or 1
        elseif cmd == "TITLE" then
            headers.title = arg
        elseif cmd == "SUBTITLE" then
            headers.subtitle = arg
        elseif cmd == "ARTIST" then
            headers.artist = arg
        elseif cmd == "SUBARTIST" then
            headers.subartist = arg
        elseif cmd == "GENRE" then
            headers.genre = arg
        elseif cmd == "BPM" then
            headers.bpm = tonumber(arg) or 130.0
        elseif cmd == "TOTAL" then
            headers.total = tonumber(arg) or 300
        elseif cmd == "RANK" then
            headers.rank = tonumber(arg) or 2
        elseif cmd:match("^WAV%w%w$") then
            local id = base36_to_int(cmd:sub(4, 5))
            headers.wav[id] = arg
        elseif cmd:match("^BMP%w%w$") then
            local id = base36_to_int(cmd:sub(4, 5))
            headers.bmp[id] = arg
        elseif cmd:match("^BPM%w%w$") then
            local id = base36_to_int(cmd:sub(4, 5))
            headers.bpm_table[id] = tonumber(arg)
        elseif cmd:match("^STOP%w%w$") then
            local id = base36_to_int(cmd:sub(5, 6))
            headers.stop_table[id] = tonumber(arg)
        end
        
        ::continue::
    end
    
    return headers
end

function BmsParser:parse_channels(lines)
    -- channels[measure][channel] = raw_data
    local channels = {}
    local warnings = {}
    
    for _, line in ipairs(lines) do
        local measure_str, channel_str, data = line:match("^#(%d%d%d)(%d%d):(.+)$")
        if not measure_str then goto continue end
        
        local measure = tonumber(measure_str)
        local channel = tonumber(channel_str)
        
        channels[measure] = channels[measure] or {}
        
        if channel == 2 then
            -- 小節長変更: 数値として保存（特別扱い）
            channels[measure][channel] = tonumber(data) or 1.0
        else
            -- 【data 前処理】
            -- 1. 空白除去（スペース、タブ）
            data = data:gsub("%s+", "")
            
            -- 2. 偶数長チェック
            if #data % 2 ~= 0 then
                table.insert(warnings, {
                    type = "odd_length_data",
                    measure = measure,
                    channel = channel,
                    original = data,
                })
                -- 末尾を切り捨てて偶数に
                data = data:sub(1, #data - 1)
            end
            
            -- 3. 空でなければ保存
            if #data > 0 then
                channels[measure][channel] = data
            end
        end
        
        ::continue::
    end
    
    return channels, warnings
end

function BmsParser:build_chart(headers, channels)
    local chart = UniversalChart:new()
    
    -- メタデータ
    chart.meta.format_source = "bms"
    chart.meta.title = headers.title
    chart.meta.subtitle = headers.subtitle
    chart.meta.artist = headers.artist
    chart.meta.subartist = headers.subartist
    chart.meta.genre = headers.genre
    
    -- スコアリングパラメータ
    chart.scoring.total = headers.total
    chart.scoring.rank = headers.rank
    
    -- タイミング
    chart.timing.initial_bpm = headers.bpm
    
    -- サウンドリソース
    for id, path in pairs(headers.wav) do
        chart.sounds.keysounds[id] = { path = path, buffer = nil }
    end
    
    -- 小節長倍率を収集
    local measure_scales = {}
    local max_measure = 0
    for measure, ch_data in pairs(channels) do
        max_measure = math.max(max_measure, measure)
        if ch_data[2] then
            measure_scales[measure] = ch_data[2]
        end
    end
    chart.timing.measure_scales = measure_scales
    
    -- measure → tick 変換テーブル構築
    local measure_start_ticks = { [0] = 0 }
    local current_tick = 0
    for m = 0, max_measure do
        measure_start_ticks[m] = current_tick
        local scale = measure_scales[m] or 1.0
        current_tick = current_tick + math.floor(TICKS_PER_MEASURE * scale)
    end
    
    -- 小節線生成
    for m = 0, max_measure do
        table.insert(chart.measures, {
            tick = measure_start_ticks[m],
            number = m,
        })
    end
    
    -- タイミングイベント収集
    local timing_events = {}
    
    -- チャンネルデータをイベントに変換
    local notes = {}
    local bgm_events = {}
    
    for measure, ch_data in pairs(channels) do
        local measure_tick = measure_start_ticks[measure]
        local measure_length = math.floor(TICKS_PER_MEASURE * (measure_scales[measure] or 1.0))
        
        for channel, data in pairs(ch_data) do
            if channel == 2 then
                -- 小節長変更は処理済み
                goto continue_channel
            end
            
            if type(data) ~= "string" then
                goto continue_channel
            end
            
            -- 2文字単位でパース
            local obj_count = #data / 2
            for i = 0, obj_count - 1 do
                local obj_str = data:sub(i * 2 + 1, i * 2 + 2)
                local obj_id = base36_to_int(obj_str)
                
                -- 【nil チェック】無効な base36 はスキップ
                if obj_id == nil then
                    goto continue_obj
                end
                
                if obj_id == 0 then
                    -- "00" は空
                    goto continue_obj
                end
                
                local tick = measure_tick + math.floor(measure_length * i / obj_count)
                
                if channel == 1 then
                    -- BGM
                    table.insert(bgm_events, { tick = tick, sound_id = obj_id })
                    
                elseif channel == 3 then
                    -- BPM変更 (16進数直接指定)
                    local bpm = tonumber(obj_str, 16)
                    if bpm and bpm > 0 then
                        table.insert(timing_events, { tick = tick, type = "bpm", value = bpm })
                    end
                    
                elseif channel == 8 then
                    -- BPM変更 (拡張)
                    local bpm = headers.bpm_table[obj_id]
                    if bpm then
                        table.insert(timing_events, { tick = tick, type = "bpm", value = bpm })
                    end
                    
                elseif channel == 9 then
                    -- STOP
                    local stop_units = headers.stop_table[obj_id]
                    if stop_units then
                        -- 【STOP を us で直接計算】
                        -- stop_units は 1/192拍単位
                        -- その時点の BPM が必要だが、ここでは初期BPMを使用
                        -- （正確にはパス2で再計算が必要）
                        local current_bpm = headers.bpm
                        -- 1/192拍 @ BPM = 60秒 / BPM / 192 秒 = 60_000_000 / BPM / 192 us
                        local stop_duration_us = math.floor(stop_units * 60000000 / (current_bpm * 192))
                        table.insert(timing_events, { 
                            tick = tick, 
                            type = "stop", 
                            value = stop_duration_us,  -- us 直接指定
                            _stop_units = stop_units,  -- 再計算用に保持
                            _bpm_at_parse = current_bpm,
                        })
                    end
                    
                elseif channel >= 11 and channel <= 19 then
                    -- 1P ノーツ
                    local lane = channel - 10  -- 1-9
                    table.insert(notes, {
                        tick = tick,
                        lane = lane,
                        type = "normal",
                        sound_id = obj_id,
                    })
                    
                elseif channel >= 21 and channel <= 29 then
                    -- 2P ノーツ (1P同等にマップ)
                    local lane = channel - 20 + 10  -- 11-19
                    table.insert(notes, {
                        tick = tick,
                        lane = lane,
                        type = "normal",
                        sound_id = obj_id,
                    })
                end
                
                ::continue_obj::
            end
            
            ::continue_channel::
        end
    end
    
    -- ソート
    table.sort(timing_events, function(a, b) return a.tick < b.tick end)
    table.sort(notes, function(a, b) return a.tick < b.tick end)
    table.sort(bgm_events, function(a, b) return a.tick < b.tick end)
    
    -- 【STOP duration 再計算】BPM変化を考慮
    timing_events = self:recalculate_stop_durations(timing_events, headers.bpm)
    
    chart.timing.events = timing_events
    chart.notes = notes
    chart.bgm = bgm_events
    
    return chart
end

-- STOP duration の再計算（BPM変化を考慮）
function BmsParser:recalculate_stop_durations(events, initial_bpm)
    local current_bpm = initial_bpm
    
    for _, event in ipairs(events) do
        if event.type == "bpm" then
            current_bpm = event.value
        elseif event.type == "stop" then
            -- _stop_units が保持されていれば正確なBPMで再計算
            if event._stop_units then
                event.value = math.floor(event._stop_units * 60000000 / (current_bpm * 192))
                -- 一時フィールドを削除
                event._stop_units = nil
                event._bpm_at_parse = nil
            end
        end
    end
    
    return events
end
```

### 1.2 オーディオシステム

```lua
---@class AudioManager
AudioManager = {
    -- バッファ
    buffers = {},           -- [SoundID] = AudioBuffer
    
    -- ボイス管理
    voices = {},            -- Voice[]
    max_voices = 64,
    
    -- 設定
    config = {
        master_volume = 1.0,
        key_volume = 1.0,
        bgm_volume = 0.8,
    },
}

---@class Voice
---@field buffer AudioBuffer
---@field start_time_us TimeUS
---@field volume number
---@field priority number

function AudioManager:init()
    -- ボイスプール初期化
    for i = 1, self.max_voices do
        self.voices[i] = {
            buffer = nil,
            active = false,
            start_time_us = 0,
            volume = 1.0,
            priority = 0,
        }
    end
end

function AudioManager:preload(chart)
    for id, sound in pairs(chart.sounds.keysounds) do
        local path = sound.path
        local buffer = self:load_audio_file(path)
        if buffer then
            self.buffers[id] = buffer
            sound.buffer = buffer
        end
    end
end

function AudioManager:play(sound_id, volume, priority)
    local buffer = self.buffers[sound_id]
    if not buffer then return nil end
    
    local voice = self:allocate_voice(priority)
    if not voice then return nil end
    
    voice.buffer = buffer
    voice.active = true
    voice.volume = volume * self.config.master_volume
    voice.priority = priority or 0
    voice.start_time_us = get_current_time_us()
    
    -- 実際の再生開始
    self:start_voice(voice)
    
    return voice
end

function AudioManager:allocate_voice(priority)
    priority = priority or 0
    
    -- 空きボイスを探す
    for _, voice in ipairs(self.voices) do
        if not voice.active then
            return voice
        end
    end
    
    -- Voice stealing: 優先度が低い or 再生時間が長いものを止める
    local victim = nil
    local victim_score = math.huge
    
    for _, voice in ipairs(self.voices) do
        -- スコア = 優先度 * 1000000 - 経過時間
        local elapsed = get_current_time_us() - voice.start_time_us
        local score = voice.priority * 1000000 - elapsed
        if score < victim_score then
            victim = voice
            victim_score = score
        end
    end
    
    if victim and priority >= victim.priority then
        self:stop_voice(victim)
        return victim
    end
    
    return nil
end

function AudioManager:load_audio_file(path)
    -- 拡張子で分岐
    local ext = path:match("%.(%w+)$"):lower()
    
    if ext == "wav" then
        return decode_wav(path)
    elseif ext == "ogg" then
        return decode_ogg(path)
    elseif ext == "mp3" then
        return decode_mp3(path)
    end
    
    return nil
end
```

### 1.3 Conductor（時間管理）

```lua
---@class Conductor
Conductor = {}
Conductor.__index = Conductor

--[[
【オフセット体系】

judge_offset_us: 判定基準オフセット
  = global_input_us + global_audio_us + chart_offset_us
  
  - global_input_us: 入力デバイス遅延補正（ユーザー設定）
  - global_audio_us: オーディオ出力遅延補正（ユーザー設定）
  - chart_offset_us: 譜面由来（SM の OFFSET など）

audio_schedule_offset_us: オーディオ発音スケジューリング用
  = -audio_latency_us（先読み分）

使い方:
  - 判定時刻 = current_time_us + judge_offset_us
  - 発音予約時刻 = current_time_us + audio_schedule_offset_us
]]

function Conductor:new()
    return setmetatable({
        -- 状態
        playing = false,
        start_real_time_us = 0,
        pause_time_us = 0,
        
        -- 現在位置
        current_time_us = 0,
        current_tick = 0,
        current_beat = 0.0,
        
        -- 参照
        timing_map = nil,
        
        -- オフセット（合成済み）
        judge_offset_us = 0,
        audio_schedule_offset_us = 0,
    }, self)
end

-- オフセット設定（PlayScene:init で呼ぶ）
function Conductor:configure_offsets(config, chart)
    -- 判定オフセット = 入力遅延 + オーディオ遅延 + 譜面由来
    self.judge_offset_us = 
        (config.offset.global_input_us or 0) +
        (config.offset.global_audio_us or 0) +
        (chart.timing.offset_us or 0)
    
    -- オーディオスケジューリングオフセット（先読み用、負の値）
    self.audio_schedule_offset_us = -(config.offset.audio_latency_us or 0)
end

function Conductor:start(timing_map)
    self.timing_map = timing_map
    self.playing = true
    self.start_real_time_us = get_current_time_us()
    self.current_time_us = 0
end

function Conductor:update()
    if not self.playing then return end
    
    local now_real = get_current_time_us()
    self.current_time_us = now_real - self.start_real_time_us
    
    -- time → tick 変換
    self.current_tick = self.timing_map:time_to_tick(self.current_time_us)
    self.current_beat = self.timing_map:tick_to_beat(self.current_tick)
end

function Conductor:pause()
    self.playing = false
    self.pause_time_us = self.current_time_us
end

function Conductor:resume()
    self.playing = true
    self.start_real_time_us = get_current_time_us() - self.pause_time_us
end

-- 判定用時刻取得
function Conductor:get_judge_time_us()
    return self.current_time_us + self.judge_offset_us
end

-- オーディオ発音スケジューリング用時刻取得
function Conductor:get_audio_time_us()
    return self.current_time_us + self.audio_schedule_offset_us
end
```

### 1.4 ゲームループ

```lua
---@class PlayScene
PlayScene = {
    chart = nil,
    timing_map = nil,
    conductor = nil,
    audio = nil,
    
    -- インデックス（処理済み位置）
    next_note_idx = 1,
    next_bgm_idx = 1,
    
    -- 入力状態
    lane_states = {},  -- [lane] = { pressed = false }
    
    -- 描画パラメータ
    scroll_speed = 3.0,
    pixels_per_beat = 200,
}

function PlayScene:init(chart, config)
    self.chart = chart
    self.timing_map = chart.timing_map
    self.conductor = Conductor:new()
    self.audio = AudioManager:new()
    
    -- 【オフセット設定】
    self.conductor:configure_offsets(config, chart)
    
    -- オーディオプリロード
    self.audio:preload(chart)
    
    -- レーン状態初期化
    for lane = 1, chart.mode.lanes do
        self.lane_states[lane] = { pressed = false }
    end
end

function PlayScene:start()
    self.conductor:start(self.timing_map)
end

function PlayScene:update(dt)
    -- 1. 時間更新
    self.conductor:update()
    
    -- 2. BGM発音処理
    self:process_bgm()
    
    -- 3. 入力処理
    self:process_input()
end

function PlayScene:process_bgm()
    -- 【audio_schedule_offset を使用】
    local audio_time = self.conductor:get_audio_time_us()
    
    while self.next_bgm_idx <= #self.chart.bgm do
        local bgm = self.chart.bgm[self.next_bgm_idx]
        
        if bgm.time_us > audio_time then
            break
        end
        
        -- BGM発音
        self.audio:play(bgm.sound_id, self.audio.config.bgm_volume, 0)
        self.next_bgm_idx = self.next_bgm_idx + 1
    end
end

function PlayScene:process_input()
    -- 入力イベント取得
    local events = get_input_events()  -- { lane, pressed, time_us }
    
    for _, event in ipairs(events) do
        if event.pressed then
            self:on_key_press(event.lane, event.time_us)
        else
            self:on_key_release(event.lane, event.time_us)
        end
    end
end

function PlayScene:on_key_press(lane, raw_input_time_us)
    self.lane_states[lane].pressed = true
    
    -- 【judge_offset を入力時刻に適用】
    local input_time_us = raw_input_time_us + self.conductor.judge_offset_us
    
    -- Phase 1: 判定なし、最も近いノーツを消す＆キー音再生
    local note = self:find_nearest_note(lane, input_time_us)
    if note and not note.hit then
        note.hit = true
        
        -- キー音再生
        if note.sound_id then
            self.audio:play(note.sound_id, self.audio.config.key_volume, 1)
        end
    end
end

function PlayScene:on_key_release(lane, raw_input_time_us)
    self.lane_states[lane].pressed = false
end

function PlayScene:find_nearest_note(lane, time_us)
    local best = nil
    local best_diff = math.huge
    local window = 200000  -- 200ms (Phase 1 は緩め)
    
    for i = self.next_note_idx, #self.chart.notes do
        local note = self.chart.notes[i]
        
        -- 過去すぎるものはスキップ
        if note.time_us < time_us - window then
            goto continue
        end
        
        -- 未来すぎるものは終了
        if note.time_us > time_us + window then
            break
        end
        
        if note.lane == lane and not note.hit then
            local diff = math.abs(note.time_us - time_us)
            if diff < best_diff then
                best = note
                best_diff = diff
            end
        end
        
        ::continue::
    end
    
    return best
end

function PlayScene:render()
    self:render_lanes()
    self:render_notes()
    self:render_judgment_line()
end

function PlayScene:render_notes()
    local current_beat = self.conductor.current_beat
    local visible_beats = 4.0 / self.scroll_speed  -- 画面内に見える拍数
    
    for i = self.next_note_idx, #self.chart.notes do
        local note = self.chart.notes[i]
        
        if note.hit then
            goto continue
        end
        
        local note_beat = self.timing_map:tick_to_beat(note.tick)
        local beat_diff = note_beat - current_beat
        
        -- 画面外（過去）
        if beat_diff < -0.5 then
            goto continue
        end
        
        -- 画面外（未来）
        if beat_diff > visible_beats then
            break
        end
        
        -- Y座標計算 (beat基準)
        local y = self:beat_diff_to_y(beat_diff)
        local x = self:lane_to_x(note.lane)
        
        draw_note(x, y, note.lane)
        
        ::continue::
    end
end

function PlayScene:beat_diff_to_y(beat_diff)
    -- beat_diff > 0: 未来（画面上方）
    -- beat_diff = 0: 判定ライン
    -- beat_diff < 0: 過去（画面下方）
    return self.judgment_line_y - beat_diff * self.pixels_per_beat * self.scroll_speed
end
```

### 1.5 Phase 1 完了基準

- [ ] BMSファイルをパースできる（#WAV, #BPM, チャンネル）
- [ ] base36 ID が正しく変換される
- [ ] 小節長変更 (#xxx02) が正しく処理される
- [ ] TimingMap が構築される
- [ ] BPM変更、STOP が TimingMap に反映される
- [ ] キー音がプリロードされる
- [ ] BGM が正しいタイミングで再生される
- [ ] ノーツが beat 基準で画面上を流れる
- [ ] キー入力でノーツが消える＆キー音が鳴る
- [ ] 最後まで演奏できる

---

## フェーズ2: 判定・スコア・ゲージ

### 2.1 判定システム

#### 判定ウィンドウ（単位統一: us）

```lua
-- 判定ウィンドウ (マイクロ秒)
JudgmentWindows = {
    lr2_normal = {
        pgreat = 18000,    -- ±18ms = ±18000us
        great  = 40000,
        good   = 100000,
        bad    = 200000,
    },
    
    beatoraja = {
        pgreat = 20000,
        great  = 60000,
        good   = 150000,
        bad    = 250000,
    },
    
    iidx = {
        pgreat = 16670,    -- 1F @60fps
        great  = 33340,
        good   = 116670,
        bad    = 250000,
    },
}

-- #RANK による補正
RankMultiplier = {
    [0] = 0.5,   -- VERY HARD
    [1] = 0.75,  -- HARD
    [2] = 1.0,   -- NORMAL
    [3] = 1.25,  -- EASY
}

function apply_rank(windows, rank)
    local mult = RankMultiplier[rank] or 1.0
    local result = {}
    for k, v in pairs(windows) do
        result[k] = math.floor(v * mult)
    end
    return result
end
```

#### 判定エンジン（責務分離）

```lua
---@class JudgeEngine
JudgeEngine = {
    windows = nil,
    
    -- ノーツ候補管理（レーン別）
    note_queues = {},  -- [lane] = { notes sorted by time }
    queue_heads = {},  -- [lane] = next index to check
    
    -- 統計
    stats = {
        pgreat = 0,
        great = 0,
        good = 0,
        bad = 0,
        poor = 0,       -- 空POOR
        miss = 0,       -- 見逃しPOOR
        
        combo = 0,
        max_combo = 0,
        
        fast = 0,
        slow = 0,
        
        -- 詳細 (FAST/SLOW 内訳)
        pgreat_fast = 0, pgreat_slow = 0,
        great_fast = 0, great_slow = 0,
        good_fast = 0, good_slow = 0,
    },
}

function JudgeEngine:init(chart, windows_preset, rank)
    local base_windows = JudgmentWindows[windows_preset] or JudgmentWindows.lr2_normal
    self.windows = apply_rank(base_windows, rank)
    
    -- レーン別ノーツキュー構築
    local lanes = chart.mode.lanes
    for lane = 1, lanes do
        self.note_queues[lane] = {}
        self.queue_heads[lane] = 1
    end
    
    for _, note in ipairs(chart.notes) do
        table.insert(self.note_queues[note.lane], note)
    end
end

-- (A) ノーツ候補選択
function JudgeEngine:find_candidate(lane, input_time_us)
    local queue = self.note_queues[lane]
    local head = self.queue_heads[lane]
    
    local best = nil
    local best_diff = math.huge
    
    for i = head, #queue do
        local note = queue[i]
        
        if note.judged then
            goto continue
        end
        
        local diff = input_time_us - note.time_us
        local abs_diff = math.abs(diff)
        
        -- BAD窓の外（過去）→ スキップ
        if diff > self.windows.bad then
            goto continue
        end
        
        -- BAD窓の外（未来）→ 終了
        if diff < -self.windows.bad then
            break
        end
        
        if abs_diff < best_diff then
            best = note
            best_diff = abs_diff
        end
        
        ::continue::
    end
    
    return best
end

-- (B) 判定評価
function JudgeEngine:evaluate(diff_us)
    local abs_diff = math.abs(diff_us)
    
    if abs_diff <= self.windows.pgreat then
        return "pgreat"
    elseif abs_diff <= self.windows.great then
        return "great"
    elseif abs_diff <= self.windows.good then
        return "good"
    elseif abs_diff <= self.windows.bad then
        return "bad"
    else
        return nil  -- 範囲外
    end
end

-- 入力処理
function JudgeEngine:on_key_press(lane, input_time_us)
    local note = self:find_candidate(lane, input_time_us)
    
    if not note then
        -- 空POOR
        self:record_judgment("poor", 0)
        return "poor", 0, nil
    end
    
    local diff = input_time_us - note.time_us
    local result = self:evaluate(diff)
    
    if result then
        note.judged = true
        note.judgment = result
        note.diff_us = diff
        
        self:record_judgment(result, diff)
        self:advance_queue_head(lane)
        
        return result, diff, note
    else
        -- BAD窓内だが何かの理由で判定できない（通常到達しない）
        return nil, diff, nil
    end
end

-- 見逃しMISS処理（毎フレーム呼ぶ）
function JudgeEngine:process_misses(current_time_us)
    local missed_notes = {}
    
    for lane, queue in pairs(self.note_queues) do
        local head = self.queue_heads[lane]
        
        for i = head, #queue do
            local note = queue[i]
            
            if note.judged then
                goto continue
            end
            
            local diff = current_time_us - note.time_us
            
            if diff > self.windows.bad then
                -- 見逃しMISS
                note.judged = true
                note.judgment = "miss"
                
                self:record_judgment("miss", diff)
                table.insert(missed_notes, note)
            else
                -- まだ判定可能時間内
                break
            end
            
            ::continue::
        end
        
        self:advance_queue_head(lane)
    end
    
    return missed_notes
end

function JudgeEngine:record_judgment(result, diff_us)
    self.stats[result] = self.stats[result] + 1
    
    -- FAST/SLOW記録
    if result ~= "poor" and result ~= "miss" then
        if diff_us < 0 then
            self.stats.fast = self.stats.fast + 1
            self.stats[result .. "_fast"] = (self.stats[result .. "_fast"] or 0) + 1
        elseif diff_us > 0 then
            self.stats.slow = self.stats.slow + 1
            self.stats[result .. "_slow"] = (self.stats[result .. "_slow"] or 0) + 1
        end
    end
    
    -- コンボ
    if result == "pgreat" or result == "great" then
        self.stats.combo = self.stats.combo + 1
    elseif result == "good" then
        -- GOODでコンボ継続するかは設定による
        if self.config.good_breaks_combo then
            self.stats.combo = 0
        else
            self.stats.combo = self.stats.combo + 1
        end
    else
        self.stats.combo = 0
    end
    
    self.stats.max_combo = math.max(self.stats.max_combo, self.stats.combo)
end

function JudgeEngine:advance_queue_head(lane)
    local queue = self.note_queues[lane]
    local head = self.queue_heads[lane]
    
    while head <= #queue and queue[head].judged do
        head = head + 1
    end
    
    self.queue_heads[lane] = head
end
```

### 2.2 スコアリング

```lua
---@class ScoringEngine
ScoringEngine = {
    mode = "ex_score",
    
    -- 状態
    score = 0,
    ex_score = 0,
    note_count = 0,
}

-- EXスコア（シンプル、基本）
local EX_SCORE_TABLE = {
    pgreat = 2,
    great  = 1,
    good   = 0,
    bad    = 0,
    poor   = 0,
    miss   = 0,
}

function ScoringEngine:on_judgment(result)
    self.ex_score = self.ex_score + (EX_SCORE_TABLE[result] or 0)
    
    -- モード別スコア計算
    if self.mode == "ex_score" then
        self.score = self.ex_score
    elseif self.mode == "lr2" then
        self:calc_lr2_score(result)
    end
end

function ScoringEngine:calc_lr2_score(result)
    -- LR2: 最大200000 + ボーナス
    local base = 200000 / self.note_count
    local rates = {
        pgreat = 1.0,
        great  = 0.8,
        good   = 0.5,
        bad    = 0.2,
        poor   = 0,
        miss   = 0,
    }
    self.score = self.score + math.floor(base * (rates[result] or 0))
end

function ScoringEngine:get_rate()
    -- EXスコアレート (0.0 - 1.0)
    local max_ex = self.note_count * 2
    if max_ex == 0 then return 0 end
    return self.ex_score / max_ex
end

function ScoringEngine:get_dj_level()
    local rate = self:get_rate()
    if rate >= 8/9 then return "AAA"
    elseif rate >= 7/9 then return "AA"
    elseif rate >= 6/9 then return "A"
    elseif rate >= 5/9 then return "B"
    elseif rate >= 4/9 then return "C"
    elseif rate >= 3/9 then return "D"
    elseif rate >= 2/9 then return "E"
    else return "F"
    end
end
```

### 2.3 ゲージシステム（方式別関数分離）

```lua
---@class GaugeEngine
GaugeEngine = {
    gauge_type = "groove",
    value = 0.0,
    
    -- パラメータ
    total = 300,
    note_count = 0,
    
    -- 状態
    failed = false,
}

-- ゲージ定義（方式ごとに on_judgment 関数を持つ）
local GaugeTypes = {
    groove = {
        initial = 0.20,
        clear_border = 0.80,
        max = 1.0,
        can_die = false,
        
        on_judgment = function(self, engine, result)
            local total = engine.total
            local note_count = engine.note_count
            
            -- 増加: TOTAL ベース
            local increase_rates = {
                pgreat = 1.0,
                great  = 0.8,
                good   = 0.4,
                bad    = 0,
            }
            
            if increase_rates[result] then
                local inc = (total / note_count) * increase_rates[result] / 100
                engine.value = math.min(self.max, engine.value + inc)
            end
            
            -- 減少: 固定%
            local decrease = {
                bad  = 0.02,
                poor = 0.06,
                miss = 0.06,
            }
            
            if decrease[result] then
                engine.value = math.max(0, engine.value - decrease[result])
            end
        end,
    },
    
    hard = {
        initial = 1.0,
        clear_border = 0.0,
        max = 1.0,
        can_die = true,
        death_threshold = 0.0,
        
        on_judgment = function(self, engine, result)
            -- 増加: 固定量（小さい）
            local increase = {
                pgreat = 0.0016,
                great  = 0.0012,
                good   = 0.0006,
            }
            
            if increase[result] then
                engine.value = math.min(self.max, engine.value + increase[result])
            end
            
            -- 減少: ゲージ量による軽減あり
            local decrease = {
                bad  = 0.05,
                poor = 0.09,
                miss = 0.09,
            }
            
            if decrease[result] then
                local dec = decrease[result]
                
                -- 30%未満で軽減
                if engine.value < 0.30 then
                    dec = dec * 0.6
                end
                
                engine.value = engine.value - dec
                
                if engine.value <= self.death_threshold then
                    engine.value = 0
                    engine.failed = true
                end
            end
        end,
    },
    
    ex_hard = {
        initial = 1.0,
        clear_border = 0.0,
        max = 1.0,
        can_die = true,
        death_threshold = 0.0,
        
        on_judgment = function(self, engine, result)
            local increase = {
                pgreat = 0.0016,
                great  = 0.0012,
                good   = 0.0006,
            }
            
            if increase[result] then
                engine.value = math.min(self.max, engine.value + increase[result])
            end
            
            local decrease = {
                bad  = 0.10,
                poor = 0.18,
                miss = 0.18,
            }
            
            if decrease[result] then
                engine.value = engine.value - decrease[result]
                
                if engine.value <= self.death_threshold then
                    engine.value = 0
                    engine.failed = true
                end
            end
        end,
    },
    
    assist = {
        initial = 0.20,
        clear_border = 0.60,
        max = 1.0,
        can_die = false,
        
        on_judgment = function(self, engine, result)
            local total = engine.total
            local note_count = engine.note_count
            
            local increase_rates = {
                pgreat = 1.2,
                great  = 1.0,
                good   = 0.6,
                bad    = 0.2,
            }
            
            if increase_rates[result] then
                local inc = (total / note_count) * increase_rates[result] / 100
                engine.value = math.min(self.max, engine.value + inc)
            end
            
            local decrease = {
                poor = 0.04,
                miss = 0.04,
            }
            
            if decrease[result] then
                engine.value = math.max(0, engine.value - decrease[result])
            end
        end,
    },
}

function GaugeEngine:init(gauge_type, total, note_count)
    self.gauge_type = gauge_type
    self.total = total
    self.note_count = note_count
    
    local def = GaugeTypes[gauge_type]
    self.value = def.initial
    self.failed = false
end

function GaugeEngine:on_judgment(result)
    if self.failed then return end
    
    local def = GaugeTypes[self.gauge_type]
    def:on_judgment(self, result)
end

function GaugeEngine:is_cleared()
    local def = GaugeTypes[self.gauge_type]
    return self.value >= def.clear_border
end

function GaugeEngine:is_failed()
    return self.failed
end

function GaugeEngine:get_clear_type()
    if self.failed then
        return "failed"
    elseif not self:is_cleared() then
        return "failed"
    else
        -- クリアタイプはゲージ種別とスコアで決まる
        if self.gauge_type == "ex_hard" then
            return "ex_hard_clear"
        elseif self.gauge_type == "hard" then
            return "hard_clear"
        else
            return "clear"
        end
    end
end
```

### 2.4 ロングノーツ判定

```lua
-- Phase 2 で追加: LN 判定
function JudgeEngine:init_ln_support()
    -- アクティブなLN追跡
    self.active_lns = {}  -- [lane] = note (押されている最中のLN)
end

function JudgeEngine:on_key_press_ln(lane, input_time_us)
    -- 通常ノーツの判定を先に試みる
    local note = self:find_candidate(lane, input_time_us)
    
    if note and note.type == "long" then
        -- LN開始判定
        local diff = input_time_us - note.time_us
        local result = self:evaluate(diff)
        
        if result then
            note.judged = true
            note.judgment_start = result
            note.diff_start_us = diff
            
            self.active_lns[lane] = note
            
            -- 開始判定を記録（終了時にまとめて計算する方式もある）
            self:record_judgment(result, diff)
            
            return result, diff, note
        end
    elseif note then
        -- 通常ノーツ
        return self:on_key_press(lane, input_time_us)
    end
    
    return "poor", 0, nil
end

function JudgeEngine:on_key_release_ln(lane, input_time_us)
    local ln = self.active_lns[lane]
    
    if not ln then
        return nil
    end
    
    -- LN終了判定
    local diff = input_time_us - ln.end_time_us
    local result = self:evaluate(diff)
    
    if result then
        ln.judgment_end = result
        ln.diff_end_us = diff
        
        -- 終了判定を記録
        self:record_judgment(result, diff)
    else
        -- 早離し = MISS
        ln.judgment_end = "miss"
        self:record_judgment("miss", diff)
    end
    
    self.active_lns[lane] = nil
    
    return ln.judgment_end, diff, ln
end

-- LNの途中離しチェック（毎フレーム）
function JudgeEngine:check_ln_releases(lane_states, current_time_us)
    for lane, ln in pairs(self.active_lns) do
        if not lane_states[lane].pressed then
            -- 途中離し
            local diff = current_time_us - ln.end_time_us
            
            if diff < -self.windows.bad then
                -- まだ終点より十分前 = 早離しMISS
                ln.judgment_end = "miss"
                self:record_judgment("miss", diff)
                self.active_lns[lane] = nil
            end
        end
    end
end
```

### 2.5 Phase 2 完了基準

- [ ] 判定エンジン（候補選択 + 評価）実装
- [ ] PGREAT/GREAT/GOOD/BAD/POOR/MISS 判定動作
- [ ] FAST/SLOW 記録・表示
- [ ] EXスコア計算
- [ ] コンボ管理
- [ ] ゲージシステム（GROOVE/HARD/EX-HARD/ASSIST）
- [ ] クリア/フェイル判定
- [ ] ロングノーツ判定
- [ ] リザルト画面（判定内訳、DJ LEVEL）

---

## フェーズ3: 他フォーマット対応

### 3.1 フォーマット別パーサー

全パーサーは **tick を正規軸として UniversalChart を出力**。

| フォーマット | 入力軸 | 変換 |
|-------------|--------|------|
| BMS | 小節+位置 | → tick |
| bmson | pulse (tick相当) | → tick (そのまま) |
| SM/SSC | beat | → tick (×2400) |
| osu! | ms | → time_us → TimingMap逆算 → tick |

#### bmson パーサー

```lua
BmsonParser = {}

function BmsonParser:parse(json_text)
    local data = json.decode(json_text)
    local chart = UniversalChart:new()
    
    -- メタデータ
    chart.meta.format_source = "bmson"
    chart.meta.title = data.info.title or ""
    chart.meta.subtitle = data.info.subtitle or ""
    chart.meta.artist = data.info.artist or ""
    
    chart.scoring.total = data.info.total or 300
    chart.scoring.rank = data.info.judge_rank or 2
    
    -- bmson の resolution (デフォルト240)
    local resolution = data.info.resolution or 240
    local tick_scale = TICKS_PER_BEAT / resolution  -- 2400 / 240 = 10
    
    -- タイミング
    chart.timing.initial_bpm = data.info.init_bpm or 130.0
    
    -- BPM変化イベント
    if data.bpm_events then
        for _, event in ipairs(data.bpm_events) do
            local tick = math.floor(event.y * tick_scale)
            table.insert(chart.timing.events, {
                tick = tick,
                type = "bpm",
                value = event.bpm,
            })
        end
    end
    
    -- STOP
    if data.stop_events then
        for _, event in ipairs(data.stop_events) do
            local tick = math.floor(event.y * tick_scale)
            local duration_ticks = math.floor(event.duration * tick_scale)
            table.insert(chart.timing.events, {
                tick = tick,
                type = "stop",
                value = duration_ticks,
            })
        end
    end
    
    -- サウンドチャンネル
    for _, channel in ipairs(data.sound_channels or {}) do
        local sound_id = self:register_sound(chart, channel.name)
        
        for _, note in ipairs(channel.notes or {}) do
            local tick = math.floor(note.y * tick_scale)
            
            if note.c then
                -- BGM (続き再生)
                table.insert(chart.bgm, { tick = tick, sound_id = sound_id })
            else
                -- ノーツ
                local note_data = {
                    tick = tick,
                    lane = note.x,
                    type = note.l and note.l > 0 and "long" or "normal",
                    sound_id = sound_id,
                }
                
                if note.l and note.l > 0 then
                    note_data.end_tick = tick + math.floor(note.l * tick_scale)
                end
                
                table.insert(chart.notes, note_data)
            end
        end
    end
    
    -- ソート
    table.sort(chart.timing.events, function(a, b) return a.tick < b.tick end)
    table.sort(chart.notes, function(a, b) return a.tick < b.tick end)
    table.sort(chart.bgm, function(a, b) return a.tick < b.tick end)
    
    chart:build_timing()
    chart:compute_stats()
    
    return chart
end
```

#### StepMania (.sm/.ssc) パーサー

```lua
SmParser = {}

function SmParser:parse(source)
    local chart = UniversalChart:new()
    chart.meta.format_source = "sm"
    
    -- SM は beat 入力 → tick に変換
    local offset_sec = 0
    local bpms = {}
    local stops = {}
    
    -- ヘッダ解析
    for tag, value in source:gmatch("#([%w]+):([^;]*);") do
        tag = tag:upper()
        
        if tag == "TITLE" then
            chart.meta.title = value
        elseif tag == "ARTIST" then
            chart.meta.artist = value
        elseif tag == "OFFSET" then
            offset_sec = tonumber(value) or 0
        elseif tag == "BPMS" then
            -- "0.000=120.000,4.000=140.000"
            for beat_str, bpm_str in value:gmatch("([%d%.]+)=([%d%.]+)") do
                local beat = tonumber(beat_str)
                local bpm = tonumber(bpm_str)
                table.insert(bpms, { beat = beat, bpm = bpm })
            end
        elseif tag == "STOPS" then
            for beat_str, dur_str in value:gmatch("([%d%.]+)=([%d%.]+)") do
                local beat = tonumber(beat_str)
                local duration_sec = tonumber(dur_str)
                table.insert(stops, { beat = beat, duration_sec = duration_sec })
            end
        elseif tag == "MUSIC" then
            chart.sounds.music_file = value
        end
    end
    
    -- 初期BPM
    table.sort(bpms, function(a, b) return a.beat < b.beat end)
    chart.timing.initial_bpm = bpms[1] and bpms[1].bpm or 120.0
    
    -- BPM/STOP → tick 変換してイベント追加
    for _, bpm in ipairs(bpms) do
        local tick = math.floor(bpm.beat * TICKS_PER_BEAT)
        table.insert(chart.timing.events, { tick = tick, type = "bpm", value = bpm.bpm })
    end
    
    for _, stop in ipairs(stops) do
        local tick = math.floor(stop.beat * TICKS_PER_BEAT)
        -- STOP: 秒 → tick変換 (その時点のBPMが必要)
        -- 簡易実装: 最後のBPMを使う
        local current_bpm = chart.timing.initial_bpm
        for _, b in ipairs(bpms) do
            if b.beat <= stop.beat then current_bpm = b.bpm end
        end
        local stop_ticks = math.floor(stop.duration_sec * current_bpm * TICKS_PER_BEAT / 60)
        table.insert(chart.timing.events, { tick = tick, type = "stop", value = stop_ticks })
    end
    
    table.sort(chart.timing.events, function(a, b) return a.tick < b.tick end)
    
    -- NOTES解析
    for notes_block in source:gmatch("#NOTES:([^;]+);") do
        local parsed = self:parse_notes_block(notes_block)
        -- 複数難易度 → 選択 UI で使うが、ここでは最初のものを使用
        for _, note in ipairs(parsed.notes) do
            local tick = math.floor(note.beat * TICKS_PER_BEAT)
            table.insert(chart.notes, {
                tick = tick,
                lane = note.lane,
                type = note.type,
                end_tick = note.end_beat and math.floor(note.end_beat * TICKS_PER_BEAT),
            })
        end
        break
    end
    
    table.sort(chart.notes, function(a, b) return a.tick < b.tick end)
    
    chart:build_timing()
    chart:compute_stats()
    
    return chart
end
```

#### osu!mania パーサー

```lua
OsuParser = {}

function OsuParser:parse(source)
    local chart = UniversalChart:new()
    chart.meta.format_source = "osu"
    
    local section = nil
    local timing_points = {}
    local hit_objects = {}
    local key_count = 4
    
    for line in source:gmatch("[^\r\n]+") do
        local new_section = line:match("^%[(%w+)%]")
        if new_section then
            section = new_section
            goto continue
        end
        
        if section == "General" then
            local key, value = line:match("^(%w+):%s*(.+)$")
            if key == "Mode" and value ~= "3" then
                return nil, "Not mania mode"
            elseif key == "AudioFilename" then
                chart.sounds.music_file = value
            end
            
        elseif section == "Metadata" then
            local key, value = line:match("^(%w+):(.*)$")
            if key == "Title" then chart.meta.title = value
            elseif key == "Artist" then chart.meta.artist = value
            end
            
        elseif section == "Difficulty" then
            local key, value = line:match("^(%w+):(.+)$")
            if key == "CircleSize" then
                key_count = math.floor(tonumber(value) or 4)
            end
            
        elseif section == "TimingPoints" then
            -- time,beatLength,meter,sampleSet,sampleIndex,volume,uninherited,effects
            local parts = split(line, ",")
            if #parts >= 8 then
                table.insert(timing_points, {
                    time_ms = tonumber(parts[1]),
                    beat_length = tonumber(parts[2]),
                    uninherited = tonumber(parts[7]) == 1,
                })
            end
            
        elseif section == "HitObjects" then
            table.insert(hit_objects, line)
        end
        
        ::continue::
    end
    
    chart.mode.lanes = key_count
    
    -- TimingPoints → BPM/SV
    -- uninherited=1: BPM定義 (beatLength = ms per beat)
    -- uninherited=0: SV変化 (beatLength = 負の倍率)
    
    table.sort(timing_points, function(a, b) return a.time_ms < b.time_ms end)
    
    -- 最初の uninherited が初期BPM
    for _, tp in ipairs(timing_points) do
        if tp.uninherited and tp.beat_length > 0 then
            chart.timing.initial_bpm = 60000 / tp.beat_length
            break
        end
    end
    
    -- osu! は ms ベースなので、まず TimingMap を time から構築する必要がある
    -- ここでは簡易実装: 先に time→tick 用の逆TimingMapを作る
    
    local time_to_tick_map = self:build_time_to_tick_map(timing_points, chart.timing.initial_bpm)
    
    -- HitObjects
    for _, line in ipairs(hit_objects) do
        local parts = split(line, ",")
        local x = tonumber(parts[1])
        local time_ms = tonumber(parts[3])
        local obj_type = tonumber(parts[4])
        
        local lane = math.floor(x * key_count / 512) + 1
        local time_us = time_ms * 1000
        local tick = time_to_tick_map:time_to_tick(time_us)
        
        local note = {
            tick = tick,
            lane = lane,
            type = "normal",
        }
        
        -- LN check (type bit 7)
        if bit.band(obj_type, 128) ~= 0 then
            local end_time_ms = tonumber((parts[6] or ""):match("^(%d+)"))
            if end_time_ms then
                note.type = "long"
                note.end_tick = time_to_tick_map:time_to_tick(end_time_ms * 1000)
            end
        end
        
        table.insert(chart.notes, note)
    end
    
    -- BPM変化イベント
    for _, tp in ipairs(timing_points) do
        if tp.uninherited and tp.beat_length > 0 then
            local bpm = 60000 / tp.beat_length
            local tick = time_to_tick_map:time_to_tick(tp.time_ms * 1000)
            table.insert(chart.timing.events, { tick = tick, type = "bpm", value = bpm })
        end
    end
    
    table.sort(chart.notes, function(a, b) return a.tick < b.tick end)
    table.sort(chart.timing.events, function(a, b) return a.tick < b.tick end)
    
    chart:build_timing()
    chart:compute_stats()
    
    return chart
end
```

### 3.2 #RANDOM/#IF 対応 (BMS)

```lua
-- BmsParser に追加
function BmsParser:preprocess_random(lines, seed)
    math.randomseed(seed or os.time())
    
    local output = {}
    local random_stack = {}      -- 現在の RANDOM 値スタック
    local skip_stack = { false } -- 現在のスキップ状態スタック
    
    for _, line in ipairs(lines) do
        local cmd = line:match("^#(%w+)")
        
        if not cmd then
            if not skip_stack[#skip_stack] then
                table.insert(output, line)
            end
            goto continue
        end
        
        cmd = cmd:upper()
        
        if cmd == "RANDOM" then
            local max = tonumber(line:match("#RANDOM%s+(%d+)")) or 1
            local value = math.random(1, max)
            table.insert(random_stack, value)
            
        elseif cmd == "SETRANDOM" then
            local value = tonumber(line:match("#SETRANDOM%s+(%d+)")) or 1
            table.insert(random_stack, value)
            
        elseif cmd == "ENDRANDOM" then
            if #random_stack > 0 then
                table.remove(random_stack)
            end
            
        elseif cmd == "IF" then
            local n = tonumber(line:match("#IF%s+(%d+)")) or 0
            local current_random = random_stack[#random_stack] or 0
            local should_skip = (current_random ~= n) or skip_stack[#skip_stack]
            table.insert(skip_stack, should_skip)
            
        elseif cmd == "ELSEIF" then
            if #skip_stack > 1 then
                local n = tonumber(line:match("#ELSEIF%s+(%d+)")) or 0
                local current_random = random_stack[#random_stack] or 0
                
                -- 親がスキップ中ならスキップ継続
                if skip_stack[#skip_stack - 1] then
                    skip_stack[#skip_stack] = true
                else
                    -- 前の IF/ELSEIF が false だった場合のみ評価
                    skip_stack[#skip_stack] = (current_random ~= n)
                end
            end
            
        elseif cmd == "ELSE" then
            if #skip_stack > 1 then
                if not skip_stack[#skip_stack - 1] then
                    skip_stack[#skip_stack] = not skip_stack[#skip_stack]
                end
            end
            
        elseif cmd == "ENDIF" then
            if #skip_stack > 1 then
                table.remove(skip_stack)
            end
            
        else
            if not skip_stack[#skip_stack] then
                table.insert(output, line)
            end
        end
        
        ::continue::
    end
    
    return output, random_stack  -- random_stack は使用した乱数値（リプレイ用）
end
```

### 3.3 Phase 3 完了基準

- [ ] bmson パーサー実装
- [ ] StepMania (.sm/.ssc) パーサー実装
- [ ] osu!mania パーサー実装
- [ ] #RANDOM/#IF/#ENDIF 対応
- [ ] フォーマット自動判別
- [ ] 全フォーマットで TimingMap 正常動作
- [ ] 複数難易度選択 UI

---

## フェーズ4: Luaスキン・拡張システム

### 4.1 スキンAPI（読み取り専用スナップショット）

```lua
-- スキンに渡す context と state は読み取り専用

---@class SkinContext
-- スキンが参照できる読み取り専用コンテキスト
SkinContext = {
    api_version = 1,
    
    -- 画面情報
    screen_width = 1920,
    screen_height = 1080,
    
    -- モード情報
    mode = {
        type = "key",
        lanes = 7,
    },
    
    -- 設定（ユーザー設定のスナップショット）
    options = {
        scroll_speed = 3.0,
        lane_cover = 0,
        -- スキン固有オプションもここ
    },
    
    -- リソースローダー（これだけ関数）
    load_image = function(path) end,
    load_sound = function(path) end,
}

---@class PlayState
-- 毎フレーム更新される読み取り専用状態
PlayState = {
    -- 時間
    current_time_us = 0,
    current_tick = 0,
    current_beat = 0.0,
    
    -- 進行状況
    progress = 0.5,  -- 0.0 - 1.0
    
    -- スコア（スナップショット）
    score = 0,
    ex_score = 0,
    combo = 0,
    max_combo = 0,
    
    -- ゲージ
    gauge = 0.8,
    gauge_type = "groove",
    
    -- 判定統計
    stats = {
        pgreat = 100,
        great = 50,
        -- ...
    },
    
    -- 最新判定（アニメーション用）
    last_judgment = {
        result = "pgreat",
        diff_us = -5000,
        lane = 3,
        time_us = 12345678,
    },
    
    -- レーン状態
    lane_pressed = { false, true, false, ... },
    
    -- 可視ノーツ取得関数
    get_visible_notes = function(range_beats) end,
}
```

### 4.2 スキン定義

```lua
-- skin.lua
return {
    name = "Default Skin",
    author = "mane3d",
    version = "1.0.0",
    api_version = 1,  -- 互換性用
    
    supported_modes = { "7key", "5key", "9key", "4key" },
    
    scenes = {
        play = "play/scene.lua",
        select = "select/scene.lua",
        result = "result/scene.lua",
    },
    
    options = {
        {
            id = "note_style",
            name = "ノーツスタイル",
            type = "select",
            values = { "default", "flat" },
            default = "default",
        },
    },
}
```

### 4.3 拡張システム

```lua
-- 拡張ヘッダ
---@class Extension
Extension = {
    id = "my_extension",
    name = "My Extension",
    version = "1.0.0",
    
    -- リプレイ互換性のためのハッシュ
    config_hash = function(self, config)
        return hash(json.encode(config))
    end,
}

-- 拡張ポイント
ExtensionPoints = {
    -- ローダー拡張
    ["loader.register"] = function(api, loader_def) end,
    
    -- 判定フック
    ["judge.pre_judge"] = function(api, note, input_time_us) end,
    ["judge.post_judge"] = function(api, note, result, diff_us) end,
    
    -- カスタム判定窓
    ["judge.custom_window"] = function(api, window_def) end,
    
    -- カスタムゲージ
    ["gauge.custom_type"] = function(api, gauge_def) end,
    
    -- ゲームモード
    ["mode.register"] = function(api, mode_def) end,
}
```

### 4.4 Phase 4 完了基準

- [ ] スキンシステム実装
- [ ] SkinContext / PlayState API
- [ ] デフォルトスキン作成
- [ ] スキン設定 UI
- [ ] 拡張ポイント実装
- [ ] サンプル拡張作成
- [ ] api_version 互換性チェック

---

## フェーズ5: ライブラリ化・Web対応

### 5.1 公開API

```lua
-- mane3d-rhythm API
local rhythm = require("mane3d-rhythm")

-- ローダー
local chart, err = rhythm.load("path/to/song.bms")
local chart, err = rhythm.load_from_string(content, { format = "bms", encoding = "shift_jis" })

-- TimingMap
local timing_map = chart.timing_map
local time_us = timing_map:tick_to_time(tick)
local tick = timing_map:time_to_tick(time_us)

-- 判定エンジン
local judge = rhythm.create_judge({
    windows = "lr2",
    rank = chart.scoring.rank,
})
judge:init(chart)

local result, diff, note = judge:on_key_press(lane, input_time_us)
local missed = judge:process_misses(current_time_us)

-- スコアリング
local scoring = rhythm.create_scoring("ex_score", chart.stats.total_notes)
scoring:on_judgment(result)

-- ゲージ
local gauge = rhythm.create_gauge("groove", {
    total = chart.scoring.total,
    note_count = chart.stats.total_notes,
})
gauge:on_judgment(result)

-- リプレイ
local replay = rhythm.create_replay()
replay:record_input(time_us, lane, "press")
replay:save("replay.mrr")

local loaded = rhythm.load_replay("replay.mrr")
```

### 5.2 リプレイフォーマット (.mrr) v2

```lua
ReplayFormat = {
    header = {
        magic = "MRR2",
        version = 2,
        
        -- 譜面識別
        chart_hash = "sha256...",           -- ファイルハッシュ
        chart_normalized_hash = "sha256...", -- 正規化後ハッシュ（エンコード差に強い）
        chart_title = "...",
        
        -- 再現性パラメータ
        random_seed = 12345,
        random_values = { 2, 1, 3 },  -- 使用した RANDOM 値列
        
        -- 設定
        judge_windows = "lr2",
        judge_rank = 2,
        gauge_type = "groove",
        
        -- 拡張情報
        extensions = {
            -- { id = "...", version = "...", config_hash = "..." }
        },
        
        -- 結果
        score = 150000,
        ex_score = 1800,
        max_combo = 500,
        clear_type = "hard_clear",
        
        played_at = 1234567890,
    },
    
    -- 入力イベント (デルタエンコード、us単位)
    inputs = {
        -- { delta_us, lane, action }
        -- action: 1=press, 0=release
    },
    
    -- 判定結果（検証用、オプショナル）
    judgments = {
        schema_version = 1,
        data = {
            -- { note_index, result, diff_us }
        },
    },
}
```

### 5.3 オフセット体系

```lua
-- 設定ファイル
Config = {
    offset = {
        -- ユーザー設定（環境依存）
        global_input_us = 0,      -- 入力デバイス遅延補正
        global_audio_us = 0,      -- オーディオ出力遅延補正
        
        -- 自動検出可能（推奨値表示用）
        detected_audio_latency_us = 0,
    },
}

-- 判定時の最終オフセット計算
function calculate_judge_offset(config, chart)
    return config.offset.global_input_us
           + config.offset.global_audio_us
           + (chart.timing.offset_us or 0)  -- 譜面由来（SM の OFFSET など）
end
```

### 5.4 Web対応考慮

```lua
-- Core の I/O 抽象化
CoreIO = {
    -- ファイル読み込み（Webでは fetch）
    read_file = function(path) end,
    
    -- 現在時刻取得（performance.now() 相当）
    get_time_us = function() end,
}

-- オーディオ抽象化
AudioBackend = {
    -- デコード（WebAudio の decodeAudioData 相当）
    decode = function(data) end,
    
    -- 再生スケジュール
    schedule_play = function(buffer, time_us, volume) end,
}
```

### 5.5 Phase 5 完了基準

- [ ] Core / Player 分離完了
- [ ] 公開 API ドキュメント
- [ ] リプレイフォーマット v2 実装
- [ ] オフセット体系整理
- [ ] WASM ビルド
- [ ] Web デモ

---

## テスト計画

### ゴールデンデータテスト

```lua
-- TimingMap テスト（新解像度: 7680/1920）
test("BPM変化のtime変換", function()
    local map = TimingMap.build(120, {
        { tick = 7680, type = "bpm", value = 180 },
    }, 15360)  -- end_tick = 2小節
    
    -- tick=0 @ 120BPM → time=0
    assert_eq(map:tick_to_time(0), 0)
    
    -- tick=7680 (1小節) @ 120BPM
    -- 1920 tick/beat × 4 beat = 7680 tick/measure
    -- 120 BPM → 1 beat = 0.5秒 → 4 beat = 2秒 = 2000000us
    assert_eq(map:tick_to_time(7680), 2000000)
    
    -- tick=15360 (2小節) → 2秒 + 1.33秒 (@180BPM)
    -- 180 BPM → 1 beat = 0.333秒 → 4 beat = 1.333秒
    assert_close(map:tick_to_time(15360), 3333333, 100)
end)

test("STOPのtime変換 - 境界定義", function()
    -- tick=3840 (0.5小節) で 500000us (0.5秒) 停止
    local map = TimingMap.build(120, {
        { tick = 3840, type = "stop", value = 500000 },
    }, 7680)
    
    -- STOP開始tick の time = STOP分を足さない（最小時刻）
    assert_eq(map:tick_to_time(3840), 1000000)  -- 1秒
    
    -- STOP中: time→tick は stop_tick を返す
    assert_eq(map:time_to_tick(1200000), 3840)  -- 1.2秒
    assert_eq(map:time_to_tick(1400000), 3840)  -- 1.4秒
    
    -- STOP後
    -- tick=5760 は STOP後 1920tick (1拍) 進んだ位置
    -- time = 1秒(STOP前) + 0.5秒(STOP) + 0.5秒(STOP後@120BPM) = 2秒
    assert_eq(map:tick_to_time(5760), 2000000)
end)

test("末尾セグメントが生成される", function()
    local map = TimingMap.build(120, {}, 7680)
    
    -- イベントなしでも末尾まで計算可能
    assert_eq(map:tick_to_time(7680), 2000000)
    assert_eq(#map.segments, 1)
    assert_eq(map.segments[1].end_tick, 7680)
end)

test("STOP精度 - 1/192拍単位", function()
    -- 1/192拍 = 10tick (7680/4/192 = 10)
    -- 1/192拍 @ 120BPM = 60/120/192 秒 = 2.604ms = 2604us
    local map = TimingMap.build(120, {
        { tick = 1920, type = "stop", value = 2604 },  -- 1拍目で1/192拍停止
    }, 3840)
    
    -- STOP後の時刻
    local after_stop = map:tick_to_time(1920 + 10)  -- STOP終了直後
    local expected = 500000 + 2604 + 5208  -- 0.5秒 + STOP + 10tick@120BPM
    assert_close(after_stop, expected, 100)
end)
```

### BMS変換テスト

```lua
test("BMS: 基本パース", function()
    local chart, warnings = BmsParser:parse(read_file("testdata/basic.bms"))
    
    assert_eq(chart.meta.title, "Test Song")
    assert_eq(chart.timing.initial_bpm, 150)
    assert_eq(#chart.notes, 100)
    assert_eq(#warnings, 0)
end)

test("BMS: 小節長変更", function()
    local chart = BmsParser:parse(read_file("testdata/measure_scale.bms"))
    
    -- 小節4が0.5倍の長さ
    assert_eq(chart.timing.measure_scales[4], 0.5)
    
    -- 小節5の開始tick
    -- 小節0-3: 7680*4 = 30720
    -- 小節4: 7680*0.5 = 3840
    -- 合計: 34560
    assert_eq(chart.measures[6].tick, 34560)  -- measures[6] = 小節5
end)

test("BMS: data前処理 - 空白除去", function()
    local channels, warnings = BmsParser:parse_channels({
        "#00111:01 02 03 04",  -- スペースあり
    })
    
    assert_eq(channels[1][11], "01020304")
    assert_eq(#warnings, 0)
end)

test("BMS: data前処理 - 奇数長警告", function()
    local channels, warnings = BmsParser:parse_channels({
        "#00111:0102030",  -- 7文字（奇数）
    })
    
    assert_eq(#warnings, 1)
    assert_eq(warnings[1].type, "odd_length_data")
    assert_eq(channels[1][11], "010203")  -- 6文字に切り詰め
end)

test("BMS: 無効なbase36はスキップ", function()
    local chart = BmsParser:parse([[
#BPM 120
#WAV01 test.wav
#00111:01!!03
]])
    
    -- !! は無効なbase36なのでスキップされる
    -- 01 と 03 だけがノーツになる
    assert_eq(#chart.notes, 2)
end)
```

---

## 開発ロードマップ

| Phase | 期間目安 | 成果物 |
|-------|---------|--------|
| 1 | 2-3週間 | BMSが再生できる最小プレイヤー（beat基準描画） |
| 2 | 2-3週間 | 判定・スコア・ゲージ・LN |
| 3 | 3-4週間 | bmson/SM/osu!/RANDOM対応 |
| 4 | 3-4週間 | スキン・拡張システム |
| 5 | 2-3週間 | ライブラリ化、Web対応 |

---

## 参考リソース

### BMS仕様
- 本家仕様: http://bm98.yaneu.com/bm98/bmsformat.html
- hitkey拡張: https://hitkey.nekokan.dyndns.info/cmds.htm
- bmson仕様: https://bmson-spec.readthedocs.io/
- Angolmois INTERNALS: https://github.com/lifthrasiir/angolmois/blob/master/INTERNALS.md

### 既存実装参考
- beatoraja: https://github.com/exch-bms2/beatoraja
- Bemuse (bms-js): https://github.com/bemusic/bms-js
- bms-rs: https://crates.io/crates/bms-rs

### StepMania仕様
- .sm/.ssc: https://github.com/stepmania/stepmania/wiki

### osu!仕様
- .osu format: https://osu.ppy.sh/wiki/en/Client/File_formats/osu_(file_format)

### 判定情報
- 各音ゲー判定比較: https://zenius-i-vanisher.com/v5.2/thread?threadid=11990
