-- srt-resegment.lua
-- src: https://github.com/VimWei/mpv-config
-- Function:
    -- Resegment srt by synchronize plain text with whisper's word-level timestamps JSON
-- Hotkey:
    -- input.conf: Ctrl+r script-binding srt_resegment
-- ref:
    -- Python edition: https://github.com/VimWei/WhisperTranscriber

local utils = require 'mp.utils'
local options = require 'mp.options'

local opts = {
    json_file = "%s.json",
    text_file = "%s.txt",
    output_srt = "%s.srt"
}

options.read_options(opts, "srt-resegment")

function get_file_name_without_ext(path)
    if not path or path == "" then
        log("Error: Empty path provided")
        return ""
    end

    local base_filename = mp.get_property("filename/no-ext")
    if not base_filename or base_filename == "" then
        log("Error: Unable to get base filename")
        return ""
    end

    -- log("Base filename without extension: " .. base_filename)

    return base_filename
end

function get_file_paths(video_filename)
    -- log("video_filename: " .. tostring(video_filename))
    if not video_filename or video_filename == "" then
        log("Error: video_filename is empty")
        return nil, nil, nil
    end

    local working_dir = mp.get_property("working-directory")
    -- log("working_dir: " .. tostring(working_dir))

    local base_filename = get_file_name_without_ext(video_filename)
    if base_filename == "" then
        log("Error: Unable to get base filename")
        return nil, nil, nil
    end
    -- log("base_filename: " .. tostring(base_filename))

    local json_file_path_from_config, text_file_path_from_config, output_srt_path_from_config = nil, nil, nil

    if opts.json_file then
        json_file_path_from_config = utils.join_path(working_dir, string.format(opts.json_file, base_filename))
    end

    if opts.text_file then
        text_file_path_from_config = utils.join_path(working_dir, string.format(opts.text_file, base_filename))
    end

    if opts.output_srt then
        output_srt_path_from_config = utils.join_path(working_dir, string.format(opts.output_srt, base_filename))
    end

    if json_file_path_from_config then
        json_file_path = json_file_path_from_config
    end

    if text_file_path_from_config then
        text_file_path = text_file_path_from_config
    end

    if output_srt_path_from_config then
        output_srt_path = output_srt_path_from_config
    end

    return json_file_path, text_file_path, output_srt_path
end

function log(message)
    mp.msg.info(message)
end

function strip_quotes(str)
    return str:gsub("^[\"']+", ""):gsub("[\"']+$", "")
end

function fix_backslashes(str)
    return str:gsub("\\", "/")
end

function generate_srt(json_data, text)
    local lines = {}
    for line in text:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end

    local srt_content = ""
    local line_id = 1

    local json_all_words = {}
    for _, segment in ipairs(json_data.segments or {}) do
        for _, word in ipairs(segment.words or {}) do
            table.insert(json_all_words, word)
        end
    end

    local json_word_index = 1
    local matched_words_index = 1
    local previous_end_time = 0

    for _, line in ipairs(lines) do
        local txt_words = {}
        for word in line:gmatch("%S+") do
            table.insert(txt_words, word)
        end

        if #txt_words == 0 then
            goto continue
        end

        local start_time = nil
        local end_time = nil
        local matched_words = {}

        for _, txt_word in ipairs(txt_words) do
            local matched = false

            -- while json_word_index <= #json_all_words do
            while json_word_index <= #json_all_words and json_word_index <= matched_words_index + 20 do
                local json_word_info = json_all_words[json_word_index]
                if json_word_info == nil then
                    log("Warning: json_word_info is nil at index " .. json_word_index)
                    json_word_index = json_word_index + 1
                    goto continue_inner
                end

                local clean_json_word = (json_word_info.word or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("[%p%c]", ""):lower()
                local clean_txt_word = txt_word:gsub("[%p%c]", ""):lower()

                if clean_json_word == clean_txt_word then
                    if start_time == nil then
                        start_time = json_word_info.start
                    end
                    end_time = json_word_info["end"]
                    table.insert(matched_words, txt_word)
                    matched = true
                    matched_words_index = json_word_index + 1
                    break
                else
                    json_word_index = json_word_index + 1
                end

                ::continue_inner::
            end

            json_word_index = matched_words_index
            if not matched then
                log("Warning: Could not match word '" .. txt_word .. "' in line " .. line_id)
            end
        end

        if start_time == nil then
            start_time = previous_end_time
        end

        if end_time == nil then
            end_time = previous_end_time
        end

        srt_content = srt_content .. line_id .. "\n" .. format_time(start_time) .. " --> " .. format_time(end_time) .. "\n" .. line .. "\n\n"
        previous_end_time = end_time
        line_id = line_id + 1

        ::continue::
    end

    return srt_content
end

function format_time(time_in_seconds)
    local hours = math.floor(time_in_seconds / 3600)
    local minutes = math.floor((time_in_seconds % 3600) / 60)
    local seconds = math.floor(time_in_seconds % 60)
    local milliseconds = math.floor((time_in_seconds - math.floor(time_in_seconds)) * 1000)
    return string.format("%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
end

function main()
    local video_filename = mp.get_property("filename")
    local json_file_path, text_file_path, output_srt_path = get_file_paths(video_filename)
    if not json_file_path or not text_file_path or not output_srt_path then
        log("Error: Failed to get file paths")
        return
    end

    -- log("json_file_path: " .. tostring(json_file_path))
    -- log("text_file_path: " .. tostring(text_file_path))
    -- log("output_srt_path: " .. tostring(output_srt_path))

    local json_file, err
    for _, mode in ipairs({"r", "rb", "rt"}) do
        json_file, err = io.open(json_file_path, mode)
        if json_file then
            break
        else
            log("Failed to open JSON file with mode " .. mode .. ". Error: " .. tostring(err))
        end
    end

    if not json_file then
        log("Error: Cannot open JSON file: " .. json_file_path)
        return
    end

    local json_content = json_file:read("*all")
    json_file:close()

    local json_data = utils.parse_json(json_content)
    if not json_data then
        log("Error: Failed to parse JSON data")
        return
    end

    local text_file = io.open(text_file_path, "r")
    if not text_file then
        log("Error: Cannot open text file")
        return
    end
    local text = text_file:read("*all")
    text_file:close()

    local srt_content = generate_srt(json_data, text)

    local srt_file = io.open(output_srt_path, "w")
    if not srt_file then
        log("Error: Cannot create SRT file")
        return
    end
    srt_file:write(srt_content)
    srt_file:close()

    log("SRT file has been generated: " .. output_srt_path)
end

mp.add_key_binding(nil, "srt_resegment", main)
