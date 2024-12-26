-- srt-to-word-level-json.lua
-- src: https://github.com/VimWei/mpv-config
-- Function:
    -- Convert YouTube auto-generated SRT to JSON with word-level timestamps.
    -- Calculate word-level timestamps using character length as a basis.
-- Hotkey:
    -- input.conf: Ctrl+e script-binding srt_to_word_level_json
-- ref:
    -- srt-resegment.lua: resegment srt by synchronize plain text with JSON

local mp = require 'mp'
local utils = require 'mp.utils'
local options = require 'mp.options'

function log(message)
    mp.msg.info(message)
    mp.osd_message(message, 3)
end

function round(num)
    -- 将数字乘以1000，四舍五入后再除以1000，以保留3位小数
    return math.floor(num * 1000 + 0.5) / 1000
end

-- 获取输出 JSON 文件路径
function get_output_json_path()
    local base_filename = mp.get_property("filename/no-ext")
    if not base_filename or base_filename == "" then
        log("Error: Unable to get base filename")
        return nil
    end

    local working_dir = mp.get_property("working-directory")
    return utils.join_path(working_dir, base_filename .. ".json")
end

-- 读取文件内容
function read_file(file_path)
    local file = io.open(file_path, "r")
    if not file then
        log("Error: Could not open file: " .. file_path)
        return nil
    end
    local content = file:read("*all")
    file:close()
    return content
end

-- 解析 SRT 文件内容
local function parse_srt(srt_content)
    if not srt_content or srt_content == "" then
        log("Error: Empty SRT content")
        return nil
    end

    local segments = {}
    local segment_id = 0

    log("Parsing SRT content...")

    -- 时间字符串转换为秒数
    local function time_to_seconds(time_str)
        local hours, minutes, seconds, msec = time_str:match("(%d+):(%d+):(%d+),(%d+)")
        if not hours or not minutes or not seconds or not msec then
            log("Error: Invalid time format: " .. tostring(time_str))
            return nil
        end
        return tonumber(hours) * 3600 + tonumber(minutes) * 60 + tonumber(seconds) + tonumber(msec) / 1000
    end

    -- 优化后的词级别时间戳计算函数
    local function calculate_word_timestamps(words, start_time, end_time)
        local total_chars = 0
        for _, word in ipairs(words) do
            total_chars = total_chars + #word
        end

        local duration = end_time - start_time
        local char_duration = duration / total_chars
        local current_time = start_time

        local result = {}
        for _, word in ipairs(words) do
            local word_duration = #word * char_duration
            table.insert(result, {
                word = word,
                start = round(current_time),
                end_time = round(current_time + word_duration)
            })
            current_time = current_time + word_duration
        end
        return result
    end

    for block in srt_content:gmatch("(.-)\r?\n\r?\n") do
        local lines = {}
        for line in block:gmatch("[^\n]+") do
            table.insert(lines, line)
        end

        if #lines >= 3 then
            segment_id = segment_id + 1
            local start_time, end_time_str = lines[2]:match("(%d+:%d+:%d+,%d+)%s*-->%s*(%d+:%d+:%d+,%d+)")
            if not start_time or not end_time_str then
                log("Time format not found in block: " .. table.concat(lines, ", "))
                goto continue
            end

            local start_seconds = time_to_seconds(start_time)
            local end_seconds = time_to_seconds(end_time_str)

            local text = lines[3]
            if not text or text == "" then
                log("Error: No text found for segment " .. segment_id)
                goto continue
            end

            -- 收集单词
            local word_list = {}
            for word in text:gmatch("%S+") do
                table.insert(word_list, word)
            end

            -- 使用优化后的时间戳计算方法
            local words = calculate_word_timestamps(word_list, start_seconds, end_seconds)

            table.insert(segments, {
                id = segment_id - 1,
                start = round(start_seconds),
                end_time = round(end_seconds),
                text = text,
                words = words,
            })

            -- log(string.format("Processed segment %d - Start: %.2f End: %.2f Words: %d",
                -- segment_id, start_seconds, end_seconds, #word_list))
        else
            log("Not enough lines in block to form a segment.")
        end

        ::continue::
    end

    log("Finished parsing. Found " .. #segments .. " segments.")

    return {
        segments = segments,
        language = "en"
    }
end

-- 保存 JSON 数据到文件
local function save_json(data, filename)
    local function escape_string(s)
        return string.gsub(s, '["\\\n\r\t]', {
            ['"'] = '\\"',
            ['\\'] = '\\\\',
            ['\n'] = '\\n',
            ['\r'] = '\\r',
            ['\t'] = '\\t'
        })
    end

    -- 使用table来收集所有JSON片段
    local parts = {}
    table.insert(parts, '{\n  "language": "' .. data.language .. '",\n  "segments": [\n')

    for i, segment in ipairs(data.segments) do
        table.insert(parts, '    {\n')
        table.insert(parts, '      "id": ' .. segment.id .. ',\n')
        table.insert(parts, '      "start": ' .. segment.start .. ',\n')
        table.insert(parts, '      "end": ' .. segment.end_time .. ',\n')
        table.insert(parts, '      "text": "' .. escape_string(segment.text) .. '",\n')
        table.insert(parts, '      "words": [\n')

        for j, word in ipairs(segment.words) do
            table.insert(parts, '        {\n')
            table.insert(parts, '          "word": "' .. escape_string(word.word) .. '",\n')
            table.insert(parts, '          "start": ' .. word.start .. ',\n')
            table.insert(parts, '          "end": ' .. word.end_time .. '\n')
            table.insert(parts, '        }' .. (j < #segment.words and ',\n' or '\n'))
        end

        table.insert(parts, '      ]\n')
        table.insert(parts, '    }' .. (i < #data.segments and ',\n' or '\n'))
    end

    table.insert(parts, '  ]\n}')

    -- 合并所有片段
    local json_str = table.concat(parts)

    -- 写入文件
    local file = io.open(filename, "w")
    if not file then
        log("Error: Cannot create JSON file")
        return
    end
    file:write(json_str)
    file:close()
end

-- 主函数
function main()

    -- 获取输出 JSON 文件路径
    local output_json_path = get_output_json_path()

    -- 获取当前主字幕文件路径
    local sub_filename = mp.get_property("current-tracks/sub/external-filename")
    if not sub_filename then
        log("No external subtitle file loaded.")
        return
    end

    -- 确认是否为 SRT 格式
    if not sub_filename:lower():match("%.srt$") then
        log("Current subtitle is not an SRT file: " .. sub_filename)
        return
    end

    -- 读取 SRT 文件内容
    local srt_content = read_file(sub_filename)
    if not srt_content then
        log("Failed to read SRT file.")
        return
    end

    -- 解析 SRT 内容并生成 JSON 数据
    local json_data = parse_srt(srt_content)
    if not json_data.segments or #json_data.segments == 0 then
        log("No segments found in the SRT file.")
        return
    end

    -- 保存 JSON 数据到文件
    log("Starting SRT to JSON conversion.")
    save_json(json_data, output_json_path)

    log("Successfully converted SRT to JSON.")
end

mp.add_key_binding(nil, "srt_to_word_level_json", main)
