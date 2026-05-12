-- High-quality GIF generator for mpv (Windows-safe)
-- Single-pass palette + HQ dithering + working subtitles
-- Keybinds: b = start, B = end, Ctrl+b = GIF, Ctrl+Shift+b = GIF w/ subs

local mp = require 'mp'
local msg = require 'mp.msg'
local opt = require 'mp.options'

local options = {
    dir = "D:/Pictures/mpv-gifs",
    fps = 24,
    width = 480
}

local start_time = -1
local end_time = -1

-- ========================
-- Helpers
-- ========================

local function file_exists(name)
    local f = io.open(name, "r")
    if f ~= nil then io.close(f) return true else return false end
end

local function esc(s)
    return string.gsub(s, '"', '"\\""')
end

local function ffmpeg_esc(s)
    s = string.gsub(s, "\\", "\\\\")
    s = string.gsub(s, ":", "\\:")
    s = string.gsub(s, "'", "\\'")
    return s
end

local function get_selected_sub()
    local tracks = mp.get_property_native("track-list")
    if not tracks then return nil end

    for _, t in ipairs(tracks) do
        if t.type == "sub" and t.selected then
            return t.id - 1 -- ffmpeg is 0-based
        end
    end
    return nil
end

local function get_output_name()
    local filename = mp.get_property("filename/no-ext")
    local base = options.dir .. "/" .. filename

    for i = 0, 999 do
        local fn = string.format("%s_%03d.gif", base, i)
        if not file_exists(fn) then
            return fn
        end
    end

    return nil
end

-- ========================
-- Core
-- ========================

local function make_gif_internal(burn_subs)
    if start_time == -1 or end_time == -1 or start_time >= end_time then
        mp.osd_message("Invalid start/end time")
        return
    end

    local input = mp.get_property("path")
    local output = get_output_name()

    if not output then
        mp.osd_message("No available filename")
        return
    end

    local duration = end_time - start_time

    -- base filters
    local vf = string.format(
        "fps=%d,scale=%d:-1:flags=lanczos",
        options.fps,
        options.width
    )

    -- subtitles
    if burn_subs then
        local sid = get_selected_sub()
        if sid ~= nil then
            vf = vf .. string.format(
                ",subtitles='%s':si=%d",
                ffmpeg_esc(input),
                sid
            )
        else
            mp.osd_message("No active subtitle track")
        end
    end

    -- single-pass palette pipeline
	-- use floyd_steinberg for low file size
    local filtergraph = string.format(
        "%s,fps=15,scale=-1:480:flags=lanczos,split[a][b];[a]palettegen=stats_mode=full[p];[b][p]paletteuse=dither=floyd_steinberg",
        vf
    )

    local args = string.format(
		'ffmpeg -v warning -i "%s" -ss %s -t %s -an -filter_complex "%s" -y "%s"',
		esc(input),
		start_time,
		duration,
		esc(filtergraph),
		esc(output)
	)

    msg.info(args)
    mp.osd_message("Creating GIF...")
    os.execute(args)

    mp.osd_message("GIF created: " .. output)
    msg.info("GIF created: " .. output)
end

-- ========================
-- Keybind functions
-- ========================

function set_start()
    start_time = mp.get_property_number("time-pos", -1)
    mp.osd_message("Start: " .. start_time)
end

function set_end()
    end_time = mp.get_property_number("time-pos", -1)
    mp.osd_message("End: " .. end_time)
end

function make_gif()
    make_gif_internal(false)
end

function make_gif_subs()
    make_gif_internal(true)
end

-- ========================
-- Keybindings
-- ========================

mp.add_key_binding(nil, "set_start", set_start)
mp.add_key_binding(nil, "set_end", set_end)
mp.add_key_binding(nil, "make_gif", make_gif)
mp.add_key_binding(nil, "make_gif_subs", make_gif_subs)
