-- chapter-converter.lua
-- src: https://github.com/VimWei/mpv-config
-- * Function:
--     - Converts timestamps from YouTube format ("00:00 chapter title") to MPV chapter format (FFmpeg metadata).
--     - Input: Plain text file named "videoname.chapter"
--     - Output: "videoname.ext.ffmetadata"
-- * Hotkey:
--     - input.conf: Ctrl+y script-binding chapter-converter
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
    for part in string.gmatch(time_str, "([^:]+)") do
        table.insert(parts, part)
    end

    -- 处理不同的时间格式
    if #parts == 3 then
        -- 格式为 1:27:45
        hours = tonumber(parts[1]) or 0
        minutes = tonumber(parts[2]) or 0
        seconds = tonumber(parts[3]) or 0
    elseif #parts == 2 then
        -- 格式为 1:27 或 1:27.123
        minutes = tonumber(parts[1]) or 0
        seconds = tonumber(parts[2]) or 0
        if string.find(parts[2], "%.%d+") then
            seconds = math.floor(seconds)
            milliseconds = (seconds - math.floor(seconds)) * 1000
        end
    elseif #parts == 1 then
        -- 格式为 1:27.123 或 1:27
        local time, fraction = time_str:match("(%d+:%d+)%.(%d+)")
        if time and fraction then
            minutes, seconds = time:match("(%d+):(%d+)")
            minutes = tonumber(minutes) or 0
            seconds = tonumber(seconds) or 0
            milliseconds = tonumber(fraction) * 10 -- 将小数秒转换为毫秒
        else
            minutes, seconds = time_str:match("(%d+):(%d+)")
            minutes = tonumber(minutes) or 0
            seconds = tonumber(seconds) or 0
        end
    end

    -- 计算总纳秒数
    local total_nanoseconds = (hours * 3600 + minutes * 60 + seconds) * 1e9 + milliseconds * 1e6
    return total_nanoseconds
end

function main()
    local video_path = mp.get_property("path")
    local video_dir, video_name = utils.split_path(video_path)
    local name_without_ext = string.gsub(video_name, "%.%w+$", "")

    local chapter_file = utils.join_path(video_dir, name_without_ext .. ".chapter")
    local ffmetadata_file = video_path .. ".ffmetadata"

    -- 检查 .chapter 文件是否存在
    local chapter_file_info = utils.file_info(chapter_file)
    if not chapter_file_info then
        mp.msg.warn("Chapter file not found: " .. chapter_file)
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
        ffmetadata:write(string.format("title=Chapter %d %s\n", i, chapter.title))
    end

    chapter_content:close()
    ffmetadata:close()

    log("Successfully created ffmetadata file: " .. ffmetadata_file)
end

mp.add_key_binding(nil, "chapter-converter", main)
