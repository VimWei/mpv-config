-- dualsubs-init.lua
-- src: https://github.com/VimWei/mpv-config
-- Function: Automatically load dual subtitles on startup
-- dualsubs-init.conf: Primary and secondary subtitle language preferences

local options = {
    primary_langs = "zh,chs,chi,chinese",
    secondary_langs = "en,eng,english"
}

local mp_options = require 'mp.options'
mp_options.read_options(options, "dualsubs-init")

local function split_string(str, sep)
    local result = {}
    for match in (str..sep):gmatch("(.-)"..sep) do
        table.insert(result, match:lower())
    end
    return result
end

local function load_subtitle_and_secondary()
    local tracks_count = mp.get_property_number("track-list/count")
    -- mp.msg.info("Tracks count: " .. (tracks_count or "nil"))

    local primary_langs = split_string(options.primary_langs, ",")
    local secondary_langs = split_string(options.secondary_langs, ",")

    local subs = {}

    -- 1. 找到所有类型为sub的track
    if tracks_count then
        for i = 1, tracks_count do
            local track_type = mp.get_property(string.format("track-list/%d/type", i-1))
            local track_lang = mp.get_property(string.format("track-list/%d/lang", i-1))
            local track_id = mp.get_property(string.format("track-list/%d/id", i-1))

            mp.msg.info(string.format("Track %d: type=%s, lang=%s, id=%s", i, track_type, track_lang, track_id))

            if type(track_type) == "string" and track_type == "sub" then
                table.insert(subs, {id = track_id, lang = track_lang, index = i})
            end
        end
    end

    -- 2. 按规则重新排列优先级
    table.sort(subs, function(a, b)
        local a_priority = 3
        local b_priority = 3

        if a.lang then
            local a_lang = a.lang:lower()
            for _, lang in ipairs(primary_langs) do
                if a_lang:match("^" .. lang .. "$") then
                    a_priority = 1
                    break
                end
            end
            if a_priority == 3 then
                for _, lang in ipairs(secondary_langs) do
                    if a_lang:match("^" .. lang .. "$") then
                        a_priority = 2
                        break
                    end
                end
            end
        end

        if b.lang then
            local b_lang = b.lang:lower()
            for _, lang in ipairs(primary_langs) do
                if b_lang:match("^" .. lang .. "$") then
                    b_priority = 1
                    break
                end
            end
            if b_priority == 3 then
                for _, lang in ipairs(secondary_langs) do
                    if b_lang:match("^" .. lang .. "$") then
                        b_priority = 2
                        break
                    end
                end
            end
        end

        if a_priority ~= b_priority then
            return a_priority < b_priority
        else
            return a.index < b.index
        end
    end)

    -- 3. 加载字幕
    if #subs > 0 then
        mp.set_property_number("sid", subs[1].id)
        mp.msg.info(string.format("Set primary subtitle to track %d (sid %s)", subs[1].index, subs[1].id))
    end

    if #subs > 1 then
        mp.set_property_number("secondary-sid", subs[2].id)
        mp.msg.info(string.format("Set secondary subtitle to track %d (sid %s)", subs[2].index, subs[2].id))
    end
end

mp.register_event("file-loaded", load_subtitle_and_secondary)
