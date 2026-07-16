-- High-quality GIF generator for mpv (Windows-safe)
-- Single-pass palette + HQ dithering + working subtitles
-- Keybinds: b = start, B = end, Ctrl+b = GIF, Ctrl+Shift+b = GIF w/ subs

local mp = require "mp"
local msg = require "mp.msg"
local opt = require "mp.options"

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
    if f ~= nil then
        io.close(f)
        return true
    else
        return false
    end
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

-- Detect selected subtitle (external or embedded)
local function get_selected_sub()
    local tracks = mp.get_property_native("track-list")
    if not tracks then
        return nil, nil
    end

    for _, t in ipairs(tracks) do
        if t.type == "sub" and t.selected then
            if t.external then
                return "external", t["external-filename"]
            else
                return "embedded", t.id - 1 -- ffmpeg is 0-based
            end
        end
    end

    return nil, nil
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

local function read_last_error_line(logfile)
    local f = io.open(logfile, "r")
    if not f then
        return "Unknown error"
    end

    local last = nil
    for line in f:lines() do
        if line:match("%S") then -- non-empty
            last = line
        end
    end
    f:close()

    if not last then
        return "Unknown ffmpeg error"
    end

    -- clean it up a bit
    last = last:gsub("^%s+", "")
    last = last:gsub("%s+$", "")

    -- shorten common spam
    last = last:gsub("Error while filtering:.*", "Filter error")
    last = last:gsub("Failed to inject frame.*", "Filter failure")

    -- truncate long lines
    if #last > 80 then
        last = last:sub(1, 77) .. "..."
    end

    return last
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
    local vf = string.format("fps=%d,scale=%d:-1:flags=lanczos", options.fps, options.width)

    -- subtitles
    if burn_subs then
        local sub_type, sub_data = get_selected_sub()

        if sub_type == "embedded" then
            vf = vf .. string.format(",subtitles='%s':si=%d", ffmpeg_esc(input), sub_data)
        elseif sub_type == "external" then
            vf = vf .. string.format(",subtitles='%s'", ffmpeg_esc(sub_data))
        else
            mp.osd_message("No active subtitle track")
        end
    end

    -- single-pass palette pipeline
    local filtergraph =
        string.format("%s,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=floyd_steinberg", vf)

    local args =
		string.format(
		'ffmpeg -v warning -ss %s -t %s -i "%s" -an -filter_complex "%s" -y "%s"',
		start_time,
		duration,
		esc(input),
		esc(filtergraph),
		esc(output)
	)

    msg.info(args)
    mp.osd_message("Creating GIF...")

    local log = os.getenv("TEMP") .. "\\mpv_gif_log.txt"

    local cmd = string.format('%s 2> "%s"', args, log)
    local ok, reason, code = os.execute(cmd)

    -- normalize success
    local success = false
    if type(ok) == "number" then
        success = (ok == 0)
    elseif type(ok) == "boolean" then
        success = ok
    end

    -- verify output file too
    if success and file_exists(output) then
        mp.osd_message("GIF created")
        msg.info("GIF created: " .. output)
    else
        local short_err = read_last_error_line(log)
        mp.osd_message("GIF failed: " .. short_err)
        msg.error("FFmpeg failed: " .. short_err)

        os.remove(log)
    end
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
