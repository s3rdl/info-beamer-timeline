-- timeline-node / node.lua
-- Timeline v9
--  - 08–23h Timeline
--  - inline + events.json
--  - Zeit-Offset
--  - Glas-Optik + Animation
--  - Hintergrund aus config.background:
--      * Bild (JPG/PNG)
--      * oder Video (MP4/MOV etc.)
--    mit Fallback auf background.jpg

gl.setup(NATIVE_WIDTH, NATIVE_HEIGHT)

local json = require "json"
local util = require "util"

local WIDTH, HEIGHT = NATIVE_WIDTH, NATIVE_HEIGHT

local VERSION = "Timeline v9 (Video-BG + Glas + Animation)"

----------------------------------------------------------------------
-- Timeline-Konfiguration
----------------------------------------------------------------------

local DAY_START_H = 8
local DAY_END_H   = 23
local DAY_START   = DAY_START_H * 3600
local DAY_END     = DAY_END_H   * 3600
local DAY_SPAN    = DAY_END - DAY_START

-- Stunden-Offset relativ zur Systemzeit (z.B. UTC→Berlin = 1)
local TIME_OFFSET_HOURS = 1

----------------------------------------------------------------------
-- Ressourcen
----------------------------------------------------------------------

-- Hintergrund: kann Bild ODER Video sein
local bg_image = nil
local bg_video = nil

local font = resource.load_font("Roboto-Regular.ttf")

-- Basis-Texturen
local tex_bar_bg    = resource.create_colored_texture(0, 0, 0, 0.55)
local tex_glass     = resource.create_colored_texture(1, 1, 1, 0.15)
local tex_glass_top = resource.create_colored_texture(1, 1, 1, 0.30)
local tex_glass_bot = resource.create_colored_texture(0, 0, 0, 0.35)

local tex_line      = resource.create_colored_texture(1, 1, 1, 0.9)
local tex_event     = resource.create_colored_texture(0.2, 0.8, 1, 0.95)
local tex_now_line  = resource.create_colored_texture(1, 1, 0.2, 1)
local tex_clear     = resource.create_colored_texture(0.1, 0.1, 0.1, 1)

----------------------------------------------------------------------
-- Daten
----------------------------------------------------------------------

local events = {}

-- Konfiguration aus config.json (wird von node.json erzeugt)
local config = {
    background    = "background.jpg",
    events_inline = ""
}

-- für Animation
local anim_phase = 0

----------------------------------------------------------------------
-- Helper
----------------------------------------------------------------------

local function unload_background()
    bg_image = nil
    bg_video = nil
end

local function load_background(name)
    unload_background()

    if not name or name == "" then
        print("[timeline] kein Hintergrundname angegeben")
        return
    end

    -- Einfache Endungserkennung für Video
    local lower = string.lower(name)
    local is_video = lower:match("%.mp4$")
                    or lower:match("%.m4v$")
                    or lower:match("%.mov$")

    if is_video then
        -- Versuch: Video laden
        local ok, vid = pcall(resource.load_video, {
            file   = name,
            looped = true,
            audio  = false
        })
        if ok and vid then
            bg_video = vid
            print("[timeline] Video-Hintergrund geladen:", name)
            return
        else
            print("[timeline] Konnte Video nicht laden, fallback auf Bild:", name)
        end
    end

    -- Falls kein Video oder Video-Laden fehlgeschlagen: Bild versuchen
    local ok, img = pcall(resource.load_image, name)
    if ok and img then
        bg_image = img
        print("[timeline] Bild-Hintergrund geladen:", name)
    else
        print("[timeline] Konnte Hintergrund nicht laden:", name)
    end
end

-- Fallback beim Start: lokales background.jpg
load_background("background.jpg")

local function parse_hhmm(s)
    if type(s) ~= "string" then return nil end
    local h, m = s:match("^(%d%d?):(%d%d)$")
    if not h then return nil end
    h = tonumber(h); m = tonumber(m)
    if not h or not m then return nil end
    return h * 3600 + m * 60
end

local function get_now_with_offset()
    local t = os.date("*t")
    local base   = t.hour * 3600 + t.min * 60 + t.sec
    local offset = (TIME_OFFSET_HOURS or 0) * 3600
    local s      = (base + offset) % (24 * 3600)
    return {
        seconds = s,
        hour    = math.floor(s / 3600),
        min     = math.floor((s % 3600) / 60),
        sec     = math.floor(s % 60)
    }
end

local function draw_text_centered(text, x, y, size)
    if not text or text == "" then return end
    local tw = font:width(text, size)
    local tx = x - tw / 2
    font:write(tx + 2, y + 2, text, size, 0, 0, 0, 0.6)
    font:write(tx,     y,     text, size, 1, 1, 1, 1)
end

local function draw_text_left(text, x, y, size, r, g, b, a)
    if not text or text == "" then return end
    font:write(x, y, text, size, r or 1, g or 1, b or 1, a or 1)
end

----------------------------------------------------------------------
-- Events laden
----------------------------------------------------------------------

local function load_events_from_content(content)
    events = {}
    if not content or content == "" then
        print("[timeline] Events leer")
        return
    end

    local ok, data = pcall(json.decode, content)
    if not ok or not data or not data.events then
        print("[timeline] ungültiges JSON in Events")
        return
    end

    for _, e in ipairs(data.events) do
        local s  = parse_hhmm(e.start)
        local en = parse_hhmm(e["end"])
        if s and en then
            table.insert(events, {
                title = e.title or "",
                s     = s,
                e     = en
            })
        else
            print("[timeline] Event übersprungen:", e.title or "?")
        end
    end

    table.sort(events, function(a,b) return a.s < b.s end)
    print("[timeline] Events geladen:", #events)
end

local function load_events_file()
    local ok, content = pcall(resource.load_file, "events.json")
    if ok and content then
        load_events_from_content(content)
    else
        events = {}
        print("[timeline] events.json nicht lesbar")
    end
end

-- Datei-Watch: nur wenn kein inline aktiv
util.file_watch("events.json", function(raw)
    if config.events_inline and config.events_inline ~= "" then
        print("[timeline] inline aktiv – Dateiänderung ignoriert")
        return
    end
    print("[timeline] events.json geändert → reload")
    load_events_from_content(raw)
end)

-- Config-Watch: steuert inline vs. Datei + Hintergrundbild
util.json_watch("config.json", function(c)
    config = c or {}

    ------------------------------------------------------------------
    -- Hintergrund aus resource-Option:
    -- config.background ist bei resource-Option ein OBJEKT:
    -- {
    --   asset_id   = ...,
    --   asset_name = "lokaler-dateiname-im-node",
    --   filename   = "originalname",
    --   type       = "image"/"video"
    -- }
    ------------------------------------------------------------------
    local bg_name = nil

    if type(config.background) == "table" and type(config.background.asset_name) == "string" then
        bg_name = config.background.asset_name
    elseif type(config.background) == "string" and config.background ~= "" then
        bg_name = config.background
    else
        bg_name = "background.jpg"
    end

    load_background(bg_name)

    -- Events
    if config.events_inline and config.events_inline ~= "" then
        print("[timeline] inline Events aktiv")
        load_events_from_content(config.events_inline)
    else
        print("[timeline] inline leer → benutze events.json")
        load_events_file()
    end
end)

----------------------------------------------------------------------
-- Timeline-Rendering
----------------------------------------------------------------------

local BAR_HEIGHT = 160

-- Event-Balken Layout
local row_h           = 30
local row_gap         = 6
local row_offset_down = 15

local function x_for(sec)
    if sec < DAY_START then sec = DAY_START end
    if sec > DAY_END   then sec = DAY_END   end
    return WIDTH * ((sec - DAY_START) / DAY_SPAN)
end

local function draw_timeline()
    local bar_y0 = HEIGHT - BAR_HEIGHT
    local bar_y1 = HEIGHT
    local mid_y  = bar_y0 + BAR_HEIGHT / 2

    -- Animation (für "Jetzt"-Linie / Glas)
    anim_phase = (anim_phase + 0.06) % (2 * math.pi)
    local pulse = 0.5 + 0.5 * math.sin(anim_phase)

    -- Glas-Optik
    tex_bar_bg:draw(0, bar_y0, WIDTH, bar_y1)
    tex_glass:draw(0, bar_y0, WIDTH, bar_y1)
    tex_glass_top:draw(0, bar_y0, WIDTH, bar_y0 + 4)
    tex_glass_bot:draw(0, bar_y1 - 8, WIDTH, bar_y1)

    -- Mittellinie
    tex_line:draw(0, mid_y - 1, WIDTH, mid_y + 1)

    -- Stunden-Ticks & Labels (08–23)
    for h = DAY_START_H, DAY_END_H do
        local sec = h * 3600
        local x = x_for(sec)
        tex_line:draw(x - 1, mid_y + 20, x + 1, mid_y + 40)
        draw_text_centered(string.format("%02d:00", h), x, mid_y + 45, 20)
    end

    -- Events
    local base_y = mid_y - 10 + row_offset_down

    for idx, e in ipairs(events) do
        local s  = math.max(e.s, DAY_START)
        local en = math.min(e.e, DAY_END)
        if en > DAY_START and s < DAY_END then
            local x0 = x_for(s)
            local x1 = x_for(en)
            if x1 < x0 + 10 then x1 = x0 + 10 end

            local row = (idx - 1) % 3
            local ey0 = base_y - row * (row_h + row_gap)
            local ey1 = ey0 + row_h

            tex_event:draw(x0, ey0, x1, ey1)
            draw_text_centered(e.title, (x0 + x1) / 2, ey0 + (row_h / 2 - 10), 22)
        end
    end

    -- Jetzt-Linie + Uhrzeit (oberhalb des Balkens)
    local now = get_now_with_offset()
    local sec = now.seconds

    if sec >= DAY_START and sec <= DAY_END then
        local cx = x_for(sec)

        -- pulsierende Linie
        local line_alpha = 0.5 + 0.5 * pulse
        tex_now_line:draw(cx - 2, bar_y0, cx + 2, bar_y1, line_alpha)

        local time_text = string.format("%02d:%02d", now.hour, now.min)
        local time_y = bar_y0 - 36
        draw_text_centered(time_text, cx, time_y, 28)
    end
end

----------------------------------------------------------------------
-- Render
----------------------------------------------------------------------

function node.render()
    -- Hintergrund: Video > Bild > Fallback
    if bg_video then
        bg_video:draw(0, 0, WIDTH, HEIGHT)
    elseif bg_image then
        bg_image:draw(0, 0, WIDTH, HEIGHT)
    else
        tex_clear:draw(0, 0, WIDTH, HEIGHT)
    end

    draw_timeline()

--    draw_text_left(VERSION, 20, 20, 24, 1, 1, 1, 0.8)
end