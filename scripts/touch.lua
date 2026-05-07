--[[
    touch.lua - Touch control support for mpv via RDP

    Tap gestures (mbtn_left):
        Left 20%  -> sub-seek -1 (if subtitles) or seek -5
        Center 60% -> play/pause
        Right 20% -> sub-seek +1 (if subtitles) or seek +5
    Swipe gestures on video area:
        Horizontal drag -> seek (proportional to video duration)
        Vertical drag left half -> playback speed
        Vertical drag right half -> volume
]]

local assdraw = require "mp.assdraw"
local msg = require "mp.msg"

local options = {
    -- Gesture options
    gesture_enabled = true,
    gesture_deadzone = 50,
    gesture_seek_scale = 1.0,
    gesture_speed_min = 0.1,
    gesture_speed_max = 5.0,
    gesture_seek_exact_delay = 0.05,
    -- Tap zone boundaries (fraction of screen width)
    tap_zone_left = 0.20,
    tap_zone_right = 0.80,
    tap_seek_no_sub = 5,
}

require "mp.options".read_options(options, "touch")

-- State
local gesture = {
    tracking = false,
    start_x = 0,
    start_y = 0,
}

-- OSD helpers
local function get_osd_dim()
    local dim = mp.get_property_native("osd-dimensions")
    if not dim then return nil end
    return dim.w, dim.h
end

local function get_mouse_pos()
    local pos = mp.get_property_native("mouse-pos")
    return pos.x, pos.y, pos.hover
end

-- ============================================================
-- Zone-based tap action
-- ============================================================

local function tap_action(sx)
    local w = get_osd_dim()
    if not w then return end
    local frac = sx / w
    local has_sub = mp.get_property("sid") ~= "no"

    if frac < options.tap_zone_left then
        if has_sub then
            mp.command("no-osd sub-seek -1")
        else
            mp.command("seek -" .. options.tap_seek_no_sub)
        end
    elseif frac > options.tap_zone_right then
        if has_sub then
            mp.command("no-osd sub-seek 1")
        else
            mp.command("seek " .. options.tap_seek_no_sub)
        end
    else
        mp.command("cycle pause")
    end
end

-- ============================================================
-- Gesture layer: swipe to seek / volume / speed
--
-- RDP Touch Mode: mouse-pos DOES update during drag (between
-- down/up events), but the mouse_move key binding does NOT fire.
-- Solution: poll mouse-pos at high frequency (16ms) starting
-- on down. Keep polling through up. When position stabilizes
-- (no change for SETTLE_MS while finger is up), finalize.
-- ============================================================

local POLL_INTERVAL = 0.016   -- 16ms polling
local SETTLE_MS = 0.15        -- position stable for 150ms = gesture end

local gd = {
    active = false,
    kind = nil,             -- "seek" | "volume" | "speed"
    origin_x = 0, origin_y = 0,
    last_x = 0, last_y = 0,
    osd_w = 0, osd_h = 0,
    start_time = 0,
    start_vol = 0,
    start_speed = 0,
    deadzone_passed = false,
    finger_up = false,
    last_change_time = 0,
    poll_timer = nil,
    settle_timer = nil,
}

local seek_exact_timer = nil

local function gesture_action(dx, dy)
    local label = ""
    if gd.kind == "seek" then
        local dur = mp.get_property_number("duration", 0)
        if dur <= 0 then return end
        local offset = dx / gd.osd_w * dur * options.gesture_seek_scale
        local target = gd.start_time + offset
        if target < 0 then target = 0 end
        if target > dur then target = dur end
        mp.commandv("seek", target, "absolute+keyframes")
        if seek_exact_timer then seek_exact_timer:kill() end
        seek_exact_timer = mp.add_timeout(options.gesture_seek_exact_delay, function()
            mp.commandv("seek", target, "absolute+exact")
        end)
        local pos = mp.get_property_number("time-pos", 0)
        local function fmt(t)
            local s = math.floor(t)
            return string.format("%d:%02d:%02d",
                math.floor(s / 3600), math.floor(s % 3600 / 60), s % 60)
        end
        label = fmt(pos) .. " / " .. fmt(dur)
    elseif gd.kind == "volume" then
        local delta = -dy / gd.osd_h * 100
        local vol = gd.start_vol + delta
        if vol < 0 then vol = 0 end
        local max = mp.get_property_number("volume-max", 100)
        if vol > max then vol = max end
        mp.set_property_number("volume", vol)
        label = "Volume: " .. math.floor(vol + 0.5) .. "%"
    elseif gd.kind == "speed" then
        local range = options.gesture_speed_max - options.gesture_speed_min
        local delta = -dy / gd.osd_h * range
        local spd = gd.start_speed + delta
        if spd < options.gesture_speed_min then spd = options.gesture_speed_min end
        if spd > options.gesture_speed_max then spd = options.gesture_speed_max end
        spd = math.floor(spd * 10 + 0.5) / 10
        mp.set_property_number("speed", spd)
        label = string.format("Speed: %.1fx", spd)
    end
    if label ~= "" then
        local ass = assdraw.ass_new()
        ass:new_event()
        ass:pos(gd.osd_w / 2, gd.osd_h * 0.20)
        ass:append("{\\an5\\fs48\\bord3\\shad0\\1c&HFFFFFF&\\3c&H000000&\\4a&H40&}")
        ass:append(label)
        mp.set_osd_ass(gd.osd_w, gd.osd_h, ass.text)
    end
end

local function clear_gesture_osd()
    mp.set_osd_ass(gd.osd_w, gd.osd_h, "")
end

local function gesture_finalize()
    if not gd.deadzone_passed then
        -- Tap: zone-based action
        tap_action(gd.origin_x)
    end
    if gd.poll_timer then gd.poll_timer:kill(); gd.poll_timer = nil end
    if gd.settle_timer then gd.settle_timer:kill(); gd.settle_timer = nil end
    if seek_exact_timer then seek_exact_timer:kill(); seek_exact_timer = nil end
    gd.active = false
    gd.finger_up = false
    clear_gesture_osd()
    mp.set_property_bool("user-data/touch/gesture-active", false)
end

local function gesture_poll_tick()
    if not gd.active then return end
    local pos = mp.get_property_native("mouse-pos")
    if not pos then return end
    local sx, sy = pos.x, pos.y
    local dx = sx - gd.origin_x
    local dy = sy - gd.origin_y
    local dist = math.sqrt(dx * dx + dy * dy)

    local moved = (sx ~= gd.last_x or sy ~= gd.last_y)
    gd.last_x = sx
    gd.last_y = sy

    if moved then
        gd.last_change_time = mp.get_time()
        if gd.finger_up and gd.settle_timer then
            gd.settle_timer:kill()
            gd.settle_timer = nil
        end
    end

    -- Deadzone check
    if not gd.deadzone_passed then
        if dist < options.gesture_deadzone then
            -- If finger is up and position settled without passing deadzone -> tap
            if gd.finger_up and not moved and not gd.settle_timer then
                gd.settle_timer = mp.add_timeout(SETTLE_MS, function()
                    gesture_finalize()
                end)
            end
            return
        end
        gd.deadzone_passed = true
        if dx * dx >= dy * dy then
            gd.kind = "seek"
        else
            if gd.origin_x < gd.osd_w / 2 then
                gd.kind = "speed"
            else
                gd.kind = "volume"
            end
        end
    end

    -- Apply gesture action
    gesture_action(dx, dy)

    -- If finger is up and position stopped changing, finalize
    if gd.finger_up and not moved and not gd.settle_timer then
        gd.settle_timer = mp.add_timeout(SETTLE_MS, function()
            gesture_finalize()
        end)
    end
end

local function gesture_start(sx, sy)
    local w, h = get_osd_dim()
    if not w then return end
    mp.set_property_bool("user-data/touch/gesture-active", true)
    gd.active = true
    gd.kind = nil
    gd.origin_x = sx
    gd.origin_y = sy
    gd.last_x = sx
    gd.last_y = sy
    gd.osd_w = w
    gd.osd_h = h
    gd.start_time = mp.get_property_number("time-pos", 0)
    gd.start_vol = mp.get_property_number("volume", 0)
    gd.start_speed = mp.get_property_number("speed", 1)
    gd.deadzone_passed = false
    gd.finger_up = false
    gd.last_change_time = mp.get_time()
    if gd.poll_timer then gd.poll_timer:kill() end
    gd.poll_timer = mp.add_periodic_timer(POLL_INTERVAL, gesture_poll_tick)
end

-- ============================================================
-- mbtn_left handler
-- ============================================================

local function handle_down()
    local sx, sy = get_mouse_pos()
    gesture.start_x = sx
    gesture.start_y = sy
    gesture.tracking = true

    if not options.gesture_enabled then return end

    if not gd.active then
        gesture_start(sx, sy)
    end
end

local function handle_up()
    if not gesture.tracking then return end
    gesture.tracking = false

    if gd.active then
        gd.finger_up = true
    end
end

-- Bindings
mp.add_forced_key_binding("mbtn_left", "touch-mbtn-left", function(info)
    if info.event == "down" then
        handle_down()
    elseif info.event == "up" then
        handle_up()
    end
end, {complex = true})

msg.info("loaded. Swipe gestures " .. (options.gesture_enabled and "ON" or "OFF"))
