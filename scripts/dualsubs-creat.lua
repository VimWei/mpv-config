-- Usage:
--    Shift + B - create bilingual subtitles (and automatically select as default subtitles with visibility set to true)
-- Note:
--    Uses currently selected primary and secondary subtitles, supporting both external and embedded subtitles.

-- 默认样式设置
local default_secondary_style = "Arial,14,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,-1,0,0,0,100,100,0,0,1,1,0,2,1,1,6,1"
local default_primary_style = "Arial,20,&H0080FFFF,&H000000FF,&H00000000,&H00000000,-1,0,0,0,100,100,1,0,1,1,0,2,1,1,6,1"

-- 读取配置文件
local function read_config()
    local config_path = mp.find_config_file("dualsubs-creat.conf")
    if not config_path then return nil end

    local config_file = io.open(config_path, "r")
    if not config_file then return nil end

    local config = {}
    for line in config_file:lines() do
        local key, value = line:match("^([%w_]+)%s*=%s*(.+)$")
        if key and value then
            config[key] = value
        end
    end
    config_file:close()
    return config
end

-- 获取样式设置
local function get_styles()
    local config = read_config()
    local secondary_style = default_secondary_style
    local primary_style = default_primary_style

    if config then
        if config.secondary_style then
            secondary_style = config.secondary_style
        end
        if config.primary_style then
            primary_style = config.primary_style
        end
    end

    return secondary_style, primary_style
end

function srt_time_to_seconds(time)
    local major, minor = time:match("(%d%d:%d%d:%d%d),(%d%d%d)")
    local hours, mins, secs = major:match("(%d%d):(%d%d):(%d%d)")
    return hours * 3600 + mins * 60 + secs + minor / 1000
end

function ass_time_to_seconds(time)
    local hours, mins, secs, centisecs = time:match("(%d+):(%d%d):(%d%d)%.(%d%d)")
    return hours * 3600 + mins * 60 + secs + centisecs / 100
end

function seconds_to_ass_time(time)
    local hours = math.floor(time / 3600)
    local mins = math.floor(time / 60) % 60
    local secs = math.floor(time % 60)
    local milliseconds = (time * 1000) % 1000

    return string.format("%d:%02d:%02d.%02d", hours, mins, secs, milliseconds / 10)
end

function get_subtitle_files()
    local track_list = mp.get_property_native("track-list")
    local primary_sub_file = nil
    local secondary_sub_file = nil

    for _, track in ipairs(track_list) do
        if track.type == "sub" and track.selected and track["external-filename"] then
            if track["main-selection"] == 0 then
                primary_sub_file = track["external-filename"]
            elseif track["main-selection"] == 1 then
                secondary_sub_file = track["external-filename"]
            end
        end
    end

    return primary_sub_file, secondary_sub_file
end

function read_subtitles_file(subtitle_path)
    local f = io.open(subtitle_path, "r")
    if not f then return {}, {}, {} end

    local subs = {}
    local subs_start = {}
    local subs_end = {}

    local data = f:read("*all")
    f:close()
    data = string.gsub(data, "\r\n", "\n")

    local file_extension = string.match(subtitle_path, "%.([^%.]+)$")

    if file_extension == "srt" then
        for start_time, end_time, text in string.gmatch(data, "(%d%d:%d%d:%d%d,%d%d%d) %-%-> (%d%d:%d%d:%d%d,%d%d%d)\n(.-)\n\n") do
            table.insert(subs, text)
            table.insert(subs_start, srt_time_to_seconds(start_time))
            table.insert(subs_end, srt_time_to_seconds(end_time))
        end
    elseif file_extension == "ass" or file_extension == "ssa" then
        local in_events = false
        for line in string.gmatch(data, "[^\n]+") do
            if string.match(line, "^%[Events%]") then
                in_events = true
            elseif in_events and string.match(line, "^Dialogue:") then
                local _, _, start_time, end_time, text = string.find(line, "Dialogue: %d+,([^,]+),([^,]+),.-,,.-,.-,.-,(.*)")
                if start_time and end_time and text then
                    table.insert(subs, text)
                    table.insert(subs_start, ass_time_to_seconds(start_time))
                    table.insert(subs_end, ass_time_to_seconds(end_time))
                end
            end
        end
    else
        mp.msg.warn("Unsupported subtitle format: " .. file_extension)
    end

    return subs, subs_start, subs_end
end

function read_subtitles_from_video(is_secondary)
    local subs = {}
    local subs_start = {}
    local subs_end = {}

    local duration = mp.get_property_number("duration")
    local step = 0.1  -- 每次前进的秒数
    local current_time = 0

    while current_time < duration do
        if is_secondary then
            mp.set_property("secondary-sid", mp.get_property("secondary-sid"))
        else
            mp.set_property("sid", mp.get_property("sid"))
        end

        mp.commandv("seek", current_time, "absolute", "exact")
        mp.command("keypress space")  -- 暂停以确保字幕加载

        local sub_text = mp.get_property("sub-text")
        local sub_start = mp.get_property_number("sub-start")
        local sub_end = mp.get_property_number("sub-end")

        if sub_text and sub_text ~= "" and sub_start and sub_end then
            table.insert(subs, sub_text)
            table.insert(subs_start, sub_start)
            table.insert(subs_end, sub_end)
            current_time = sub_end
        else
            current_time = current_time + step
        end
    end

    return subs, subs_start, subs_end
end

function write_bilingual_subtitles(subs_primary, subs_primary_start, subs_primary_end, subs_secondary, subs_secondary_start, subs_secondary_end, subtitles_filename)
    if #subs_primary == 0 or #subs_secondary == 0 then
        return false
    end

    local screenx, screeny, aspect = mp.get_osd_size()
    mp.set_osd_ass(screenx, screeny, "{\\an9}● ")

    local f = assert(io.open(subtitles_filename, "w"))

    f:write("[Script Info]\n")
    f:write("ScriptType: v4.00+\n")
    f:write("PlayResX: 384\n")
    f:write("PlayResY: 288\n")
    f:write("ScaledBorderAndShadow: yes\n\n")

    f:write("[V4+ Styles]\n")
    f:write("Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n")
    local secondary_style, primary_style = get_styles()
    f:write(string.format("Style: Secondary,%s\n", secondary_style))
    f:write(string.format("Style: Primary,%s\n\n", primary_style))

    f:write("[Events]\n")
    f:write("Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n")

    for i, secondary_text in ipairs(subs_secondary) do
        local secondary_start = subs_secondary_start[i]
        local secondary_end = subs_secondary_end[i]
        secondary_text = string.gsub(secondary_text, "\n", "\\N")

        local primary_text = ""
        for j, prim_sub_text in ipairs(subs_primary) do
            local prim_sub_start = subs_primary_start[j]
            local prim_sub_end = subs_primary_end[j]

            if prim_sub_end > secondary_start and prim_sub_start < secondary_end then
                primary_text = prim_sub_text
                break
            end

            if prim_sub_start >= secondary_end then
                break
            end
        end

        primary_text = string.gsub(primary_text, "\n", "\\N")
        primary_text = string.gsub(primary_text, "<[^>]+>", "")

        f:write(string.format("Dialogue: 0,%s,%s,Secondary,,0,0,0,,%s\n",
                seconds_to_ass_time(secondary_start),
                seconds_to_ass_time(secondary_end),
                secondary_text))

        if primary_text ~= "" then
            f:write(string.format("Dialogue: 0,%s,%s,Primary,,0,0,0,,%s\n",
                    seconds_to_ass_time(secondary_start),
                    seconds_to_ass_time(secondary_end),
                    primary_text))
        end
    end

    f:close()

    mp.set_osd_ass(screenx, screeny, "")

    return true
end

function create_bilingual_subtitles()
    local primary_sub_path, secondary_sub_path = get_subtitle_files()

    local subs_primary, subs_primary_start, subs_primary_end
    local subs_secondary, subs_secondary_start, subs_secondary_end

    -- 处理主字幕
    if primary_sub_path then
        mp.msg.info("Primary subtitle file: " .. primary_sub_path)
        subs_primary, subs_primary_start, subs_primary_end = read_subtitles_file(primary_sub_path)
    else
        mp.msg.info("No external primary subtitle file found, reading from video")
        subs_primary, subs_primary_start, subs_primary_end = read_subtitles_from_video(false)
    end

    -- 处理次字幕
    if secondary_sub_path then
        mp.msg.info("Secondary subtitle file: " .. secondary_sub_path)
        subs_secondary, subs_secondary_start, subs_secondary_end = read_subtitles_file(secondary_sub_path)
    else
        mp.msg.info("No external secondary subtitle file found, reading from video")
        subs_secondary, subs_secondary_start, subs_secondary_end = read_subtitles_from_video(true)
    end

    -- 生成双语字幕文件
    local subtitles_filename = mp.get_property("working-directory") .. "/" .. mp.get_property("filename/no-ext") .. "_bilingual.ass"
    local ret = write_bilingual_subtitles(subs_primary, subs_primary_start, subs_primary_end,
                                          subs_secondary, subs_secondary_start, subs_secondary_end,
                                          subtitles_filename)

    if ret then
        mp.commandv("sub-add", subtitles_filename)
        mp.set_property("sub-visibility", "yes")
        mp.osd_message("Finished creating bilingual subtitles")
        mp.msg.info("Bilingual subtitle created at: " .. subtitles_filename)
    else
        mp.osd_message("Failed to create bilingual subtitles")
        mp.msg.error("Failed to create bilingual subtitles")
    end
end

mp.add_key_binding("B", "create-bilingual-subtitles", create_bilingual_subtitles)
