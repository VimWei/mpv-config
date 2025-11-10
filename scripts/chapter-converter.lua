-- chapter-converter.lua
-- src: https://github.com/VimWei/mpv-config
-- * Function:
--     - Converts chapter format between YouTube and mpv.
--     - YouTube Chapter: "videoname.chapter" (e.g., "00:10 chapter title").
--     - mpv Chapter: "videoname.ext.ffmetadata" (FFmpeg metadata standard).
-- * Hotkey customize:
--     - Ctrl+y       script-binding   youtube-to-mpv
--     - Ctrl+Alt+y   script-binding   mpv-to-youtube
-- * Ref:
--     - adding/editing/removing/saving/loading chapters
--     - https://github.com/mar04/chapters_for_mpv

local utils = require 'mp.utils'

function log(message)
    mp.msg.info(message)
    -- 是否在OSD上显示消息
    mp.osd_message(message, 3)
end

function parse_time(time_str)
    local hours, minutes, seconds, milliseconds = 0, 0, 0, 0

    -- 匹配时间格式
    local parts = {}
    for part in string.gmatch(time_str, "([^:%.]+)") do
        table.insert(parts, part)
    end

    -- 处理不同的时间格式
    if #parts == 4 then
        -- 格式为 1:27:45.200
        hours = tonumber(parts[1]) or 0
        minutes = tonumber(parts[2]) or 0
        seconds = tonumber(parts[3]) or 0
        milliseconds = tonumber(parts[4]) or 0
    elseif #parts == 3 then
        if string.find(time_str, "%.") then
            -- 格式为 1:27.200
            minutes = tonumber(parts[1]) or 0
            seconds = tonumber(parts[2]) or 0
            milliseconds = tonumber(parts[3]) or 0
        else
            -- 格式为 1:27:45
            hours = tonumber(parts[1]) or 0
            minutes = tonumber(parts[2]) or 0
            seconds = tonumber(parts[3]) or 0
        end
    elseif #parts == 2 then
        if string.find(time_str, "%.") then
            -- 格式为 27.200
            seconds = tonumber(parts[1]) or 0
            milliseconds = tonumber(parts[2]) or 0
        else
            -- 格式为 1:27
            minutes = tonumber(parts[1]) or 0
            seconds = tonumber(parts[2]) or 0
        end
    elseif #parts == 1 then
        -- 格式为 27
        seconds = tonumber(parts[1]) or 0
    end

    -- 计算总纳秒数
    local total_nanoseconds = (hours * 3600 + minutes * 60 + seconds) * 1e9 + milliseconds * 1e6
    return total_nanoseconds
end

function convert_youtube_to_mpv()
    local video_path = mp.get_property("path")
    local video_dir, video_name = utils.split_path(video_path)
    local name_without_ext = string.gsub(video_name, "%.%w+$", "")

    local ffmetadata_file = video_path .. ".ffmetadata"

    -- 优先尝试带视频后缀名的 chapter 文件，如果不存在则尝试不带后缀名的（向后兼容）
    local chapter_file_with_ext = utils.join_path(video_dir, video_name .. ".chapter")
    local chapter_file_without_ext = utils.join_path(video_dir, name_without_ext .. ".chapter")
    
    local chapter_file = nil
    local chapter_file_info = utils.file_info(chapter_file_with_ext)
    if chapter_file_info then
        chapter_file = chapter_file_with_ext
    else
        chapter_file_info = utils.file_info(chapter_file_without_ext)
        if chapter_file_info then
            chapter_file = chapter_file_without_ext
        end
    end

    if not chapter_file then
        mp.msg.warn("Chapter file not found: " .. chapter_file_with_ext .. " or " .. chapter_file_without_ext)
        return
    end

    -- 读取 .chapter 文件
    local chapter_content = io.open(chapter_file, "r")
    if not chapter_content then
        mp.msg.error("Could not open chapter file: " .. chapter_file)
        return
    end

    -- 创建 .ffmetadata 文件
    local ffmetadata = io.open(ffmetadata_file, "w")
    if not ffmetadata then
        mp.msg.error("Could not create ffmetadata file: " .. ffmetadata_file)
        chapter_content:close()
        return
    end

    -- 写入 ffmetadata 头部
    ffmetadata:write(";FFMETADATA1\n")

    local chapters = {}

    -- 解析 .chapter 文件并写入 .ffmetadata 文件
    for line in chapter_content:lines() do
        local time, title = line:match("(%d+:%d+:%d+%.?%d*)%s+(.*)")
        if not time then
            time, title = line:match("(%d+:%d+%.?%d*)%s+(.*)")
            if not time then
                -- 这种情况通常是格式为 '1:27.123' 或 '1:27'
                time, title = line:match("(%d+:%d+%.?%d*)%s+(.*)")
                if not time then
                    mp.msg.error("Invalid time format: " .. line)
                    return
                end
            end
        end

        if time and title then
            local start_time = parse_time(time)
            table.insert(chapters, {start_time = start_time, title = title})
        end
    end

    -- 写入章节信息
    for i, chapter in ipairs(chapters) do
        ffmetadata:write("[CHAPTER]\n")
        ffmetadata:write(string.format("START=%d\n", chapter.start_time))
        if i < #chapters then
            ffmetadata:write(string.format("END=%d\n", chapters[i+1].start_time))
        else
            -- 对于最后一个章节，使用视频总时长作为结束时间
            local video_duration_ns = mp.get_property_number("duration") * 1e9
            ffmetadata:write(string.format("END=%d\n", video_duration_ns))
        end
        ffmetadata:write(string.format("title=%s\n", chapter.title))
    end

    chapter_content:close()
    ffmetadata:close()

    log("Successfully created ffmetadata file: " .. ffmetadata_file)
end

function convert_mpv_to_youtube()
    local video_path = mp.get_property("path")
    local video_dir, video_name = utils.split_path(video_path)

    -- 输出带视频后缀名的 chapter 文件
    local chapter_file = utils.join_path(video_dir, video_name .. ".chapter")
    local ffmetadata_file = video_path .. ".ffmetadata"

    -- 检查 .ffmetadata 文件是否存在
    local ffmetadata_file_info = utils.file_info(ffmetadata_file)
    if not ffmetadata_file_info then
        mp.msg.warn("FFmetadata file not found: " .. ffmetadata_file)
        return
    end

    -- 读取 .ffmetadata 文件
    local ffmetadata_content = io.open(ffmetadata_file, "r")
    if not ffmetadata_content then
        mp.msg.error("Could not open ffmetadata file: " .. ffmetadata_file)
        return
    end

    -- 创建 .chapter 文件
    local chapter_content = io.open(chapter_file, "w")
    if not chapter_content then
        mp.msg.error("Could not create chapter file: " .. chapter_file)
        ffmetadata_content:close()
        return
    end

    -- 解析 .ffmetadata 文件并写入 .chapter 文件
    local in_chapter_section = false
    local chapter_start_time = 0
    local chapter_title = ""

    for line in ffmetadata_content:lines() do
        if line:match("%[CHAPTER%]") then
            in_chapter_section = true
        elseif in_chapter_section then
            local start_time_str = line:match("START=(%d+)")
            local title_str = line:match("title=(.*)")

            if start_time_str then
                chapter_start_time = tonumber(start_time_str)
            elseif title_str then
                chapter_title = title_str
                if chapter_title then
                    local formatted_start_time = format_time(chapter_start_time)
                    chapter_content:write(formatted_start_time .. " " .. chapter_title .. "\n")
                end
                in_chapter_section = false
            end
        end
    end

    ffmetadata_content:close()
    chapter_content:close()

    log("Successfully created chapter file: " .. chapter_file)
end

function format_time(nanoseconds)
    local total_seconds = math.floor(nanoseconds / 1e9)
    local hours = math.floor(total_seconds / 3600)
    local minutes = math.floor((total_seconds % 3600) / 60)
    local seconds = total_seconds % 60
    local milliseconds = math.floor((nanoseconds % 1e9) / 1e6)

    if hours > 0 then
        return string.format("%02d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
    else
        return string.format("%02d:%02d.%03d", minutes, seconds, milliseconds)
    end
end

mp.add_key_binding(nil, "youtube-to-mpv", convert_youtube_to_mpv)
mp.add_key_binding(nil, "mpv-to-youtube", convert_mpv_to_youtube)
