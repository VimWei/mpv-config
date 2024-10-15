local utils = require 'mp.utils'
local options = require 'mp.options'

local opts = {
    json_file = "whisper_wordlevel_timestamps.json",
    text_file = "srt_plain_text.txt",
    output_srt = "output.srt"
}

options.read_options(opts, "srt-resegment")

function log(message)
    mp.msg.info(message)
    -- 是否在OSD上显示消息
    -- mp.osd_message(message, 3)
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

    -- log("Total words in JSON: " .. #json_all_words)

    local json_word_index = 1
    local matched_words_index = 1
    local previous_end_time = 0

    for _, line in ipairs(lines) do
        local txt_words = {}
        for word in line:gmatch("%S+") do
            table.insert(txt_words, word)
        end

        -- log("Processing line: " .. line)
        -- log("Words in line: " .. table.concat(txt_words, ", "))

        if #txt_words == 0 then
            goto continue
        end

        local start_time = nil
        local end_time = nil
        local matched_words = {}

        for _, txt_word in ipairs(txt_words) do
            local matched = false

            while json_word_index <= #json_all_words do
                local json_word_info = json_all_words[json_word_index]
                if json_word_info == nil then
                    log("Warning: json_word_info is nil at index " .. json_word_index)
                    json_word_index = json_word_index + 1
                    goto continue_inner
                end

                local clean_json_word = (json_word_info.word or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("[%p%c]", ""):lower()
                local clean_txt_word = txt_word:gsub("[%p%c]", ""):lower()

                -- log("Comparing: '" .. clean_json_word .. "' with '" .. clean_txt_word .. "'")

                if clean_json_word == clean_txt_word then
                    if start_time == nil then
                        start_time = json_word_info.start
                    end
                    end_time = json_word_info["end"]
                    table.insert(matched_words, txt_word)
                    matched = true
                    -- log("Matched word: " .. txt_word)
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
    local working_dir = mp.get_property("working-directory")
    -- log("Working directory: " .. tostring(working_dir))

    local json_file_path = utils.join_path(working_dir, opts.json_file)
    -- log("Full JSON file path: " .. json_file_path)

    local json_file, err
    for _, mode in ipairs({"r", "rb", "rt"}) do
        json_file, err = io.open(json_file_path, mode)
        if json_file then
            -- log("Successfully opened JSON file with mode: " .. mode)
            break
        else
            -- log("Failed to open JSON file with mode " .. mode .. ". Error: " .. tostring(err))
        end
    end

    if not json_file then
        log("Error: Cannot open JSON file: " .. json_file_path)
        -- log("Error message: " .. tostring(err))
        -- log("Current directory contents:")
        local handle = io.popen("dir " .. utils.join_path(working_dir, "*.*"))
        local result = handle:read("*a")
        handle:close()
        -- log(result)
        return
    end

    local json_content = json_file:read("*all")
    json_file:close()

    -- log("JSON file content (first 100 characters):")
    -- log(json_content:sub(1, 100))

    local json_data = utils.parse_json(json_content)
    if not json_data then
        -- log("Error: Failed to parse JSON data")
        return
    end

    -- log("Text file path: " .. tostring(opts.text_file))
    local text_file_path = utils.join_path(working_dir, opts.text_file)
    -- log("Full text file path: " .. tostring(text_file_path))

    local text_file = io.open(text_file_path, "r")
    if not text_file then
        log("Error: Cannot open text file")
        return
    end
    local text = text_file:read("*all")
    text_file:close()

    local srt_content = generate_srt(json_data, text)

    local output_srt_path = utils.join_path(working_dir, opts.output_srt)
    local srt_file = io.open(output_srt_path, "w")
    if not srt_file then
        log("Error: Cannot create SRT file")
        return
    end
    srt_file:write(srt_content)
    srt_file:close()

    log("SRT file has been generated: " .. output_srt_path)
end

-- 注册一个可以被 input.conf 引用的命令
mp.add_key_binding(nil, "srt_resegment", main)
