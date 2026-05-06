-- dump-info.lua
-- src: https://github.com/VimWei/mpv-config
-- Function: Dump file info (same as pressing I) to a text file next to the video
-- Hotkey: Ctrl+I

local function append_property(s, prop, prefix, fmt, suffix)
    local val = mp.get_property_osd(prop)
    if not val or val == "" then return false end
    s[#s + 1] = "    " .. prefix .. " " .. val .. (suffix or "")
    return true
end

local function add_file(s)
    s[#s + 1] = ""
    s[#s + 1] = "File:"
    s[#s + 1] = "    " .. mp.get_property_osd("filename")
    local title = mp.get_property_osd("media-title")
    if title and title ~= "" and title ~= mp.get_property_osd("filename") then
        s[#s + 1] = "    Title: " .. title
    end
    append_property(s, "duration", "Duration:")
    -- Metadata tags
    local tags = mp.get_property_native("display-tags", {})
    for _, tag in ipairs(tags) do
        if tag ~= "Title" then
            local value = mp.get_property("metadata/by-key/" .. tag)
            if value and value ~= "" and #value < 128 then
                s[#s + 1] = "    " .. tag:gsub("_", " ") .. ": " .. value
            end
        end
    end
    -- Edition
    local editions = mp.get_property_number("editions", 0)
    local edition = mp.get_property_number("current-edition")
    if edition and editions > 1 then
        local ed_title = mp.get_property("edition-list/" .. edition .. "/title", "")
        local ed_str = ed_title ~= "" and ed_title or tostring(edition)
        s[#s + 1] = "    Edition: " .. ed_str
    end
    -- Chapter
    local ch_index = mp.get_property_number("chapter")
    if ch_index and ch_index >= 0 then
        local ch_title = mp.get_property("chapter-list/" .. ch_index .. "/title", "")
        local ch_count = mp.get_property_number("chapter-list/count", 0)
        s[#s + 1] = "    Chapter: " .. ch_title
            .. " (" .. (ch_index + 1) .. " / " .. ch_count .. ")"
    end
    append_property(s, "file-size", "Size:")
    append_property(s, "file-format", "Format/Protocol:")
end

local function add_display(s)
    local vo = mp.get_property_native("current-vo")
    if not vo then return end

    s[#s + 1] = ""
    s[#s + 1] = "Display:"
    s[#s + 1] = "    " .. vo
    local names = mp.get_property("display-names", "")
    if names and names ~= "" then
        s[#s] = s[#s] .. " (" .. names .. ")"
    end
    local ctx = mp.get_property_native("current-gpu-context")
    if ctx then
        s[#s + 1] = "    Context: " .. ctx
    end
    append_property(s, "avsync", "A-V:")
    -- FPS
    local dfps = mp.get_property_osd("display-fps", "")
    if dfps ~= "" then
        local edfps = mp.get_property_osd("estimated-display-fps", "")
        local fps_str = dfps .. " Hz"
        if edfps ~= "" and edfps ~= dfps then
            fps_str = dfps .. " Hz (specified) " .. edfps .. " Hz (estimated)"
        end
        s[#s + 1] = "    Refresh Rate: " .. fps_str
    end
    -- Dropped frames
    local decoder_drop = mp.get_property_number("decoder-frame-drop-count")
    local output_drop = mp.get_property_number("frame-drop-count")
    if decoder_drop or output_drop then
        s[#s + 1] = "    Dropped Frames: "
            .. (decoder_drop or 0) .. " (decoder) "
            .. (output_drop or 0) .. " (output)"
    end
    -- Display sync
    if mp.get_property_bool("display-sync-active", false) then
        local vs = mp.get_property_osd("video-speed-correction", "")
        local as = mp.get_property_osd("audio-speed-correction", "")
        if vs ~= "" or as ~= "" then
            s[#s + 1] = "    DS: " .. (vs or "-") .. " / " .. (as or "-")
        end
        append_property(s, "mistimed-frame-count", "Mistimed:")
        append_property(s, "vo-delayed-frame-count", "Delayed:")
        append_property(s, "vsync-ratio", "VSync Ratio:")
        append_property(s, "vsync-jitter", "VSync Jitter:")
    end
    -- Deinterlacing
    if mp.get_property_native("deinterlace-active") then
        append_property(s, "deinterlace", "Deinterlacing:")
    end
    -- Display resolution
    local rt = mp.get_property_native("video-target-params")
    if rt then
        if rt["dw"] and rt["dh"] then
            s[#s + 1] = "    Resolution: " .. rt["dw"] .. "x" .. rt["dh"]
        end
        local r = {}
        for k, v in pairs(rt) do r[k] = v end
        local scale = mp.get_property("current-window-scale", "")
        if scale ~= "" then
            s[#s + 1] = "    Window Scale: " .. scale
        end
        if r["pixelformat"] then
            s[#s + 1] = "    Format: " .. r["pixelformat"]
            if r["colorlevels"] then
                s[#s] = s[#s] .. "  Levels: " .. r["colorlevels"]
            end
        end
        if r["colormatrix"] then
            s[#s + 1] = "    Colormatrix: " .. r["colormatrix"]
        end
        if r["primaries"] then
            s[#s + 1] = "    Primaries: " .. r["primaries"]
        end
        if r["gamma"] then
            s[#s + 1] = "    Transfer: " .. r["gamma"]
        end
        -- HDR
        local hdr = r
        local function has(val, target)
            return val and math.abs(val - target) > 1e-4
        end
        local has_dml = has(hdr["min-luma"], 0.203) or has(hdr["max-luma"], 203)
        local has_cll = hdr["max-cll"] and hdr["max-cll"] > 0
        local has_fall = hdr["max-fall"] and hdr["max-fall"] > 0
        if has_dml or has_cll or has_fall then
            if has_dml then
                hdr["min-luma"] = hdr["min-luma"] <= 1e-6 and 0 or hdr["min-luma"]
                s[#s + 1] = string.format("    Display: %.2g / %.0f cd/m²",
                    hdr["min-luma"], hdr["max-luma"])
            end
            if has_cll then
                s[#s + 1] = string.format("    MaxCLL: %.0f cd/m²", hdr["max-cll"])
            end
            if has_fall then
                s[#s + 1] = "    MaxFALL: " .. hdr["max-fall"] .. " cd/m²"
            end
        end
    end
end

local function add_video(s)
    local r = mp.get_property_native("video-params")
    local ro = mp.get_property_native("video-out-params")
    if not r then r = ro end
    if not r then return end

    local track = mp.get_property_native("current-tracks/video")
    local is_image = track and track.image
    local prefix = is_image and "Image:" or "Video:"
    s[#s + 1] = ""
    s[#s + 1] = prefix
    if track then
        local desc = track["codec-desc"] or ""
        local profile = track["codec-profile"] or ""
        local line = "    " .. desc
        if profile ~= "" then line = line .. " [" .. profile .. "]" end
        if track["codec"] ~= track["decoder"] then
            line = line .. " [" .. (track["decoder"] or "") .. "]"
        end
        s[#s + 1] = line
        local hw = mp.get_property("hwdec-current", "")
        if hw and hw ~= "" and hw ~= "no" then
            s[#s + 1] = "    HW: " .. hw
        end
    end
    -- Frame rate
    if not is_image then
        local cfps = mp.get_property_osd("container-fps", "")
        local efps = mp.get_property_osd("estimated-vf-fps", "")
        if cfps ~= "" then
            local fps_str = cfps .. " fps"
            if efps ~= "" and efps ~= cfps then
                fps_str = cfps .. " fps (specified) " .. efps .. " fps (estimated)"
            end
            s[#s + 1] = "    Frame Rate: " .. fps_str
        end
    end
    -- Resolution
    if r["w"] and r["h"] then
        local res_str = r["w"] .. "x" .. r["h"]
        if r["sar"] then
            res_str = res_str .. " " .. string.format("%.2f:1", r["sar"])
            if r["sar-name"] then res_str = res_str .. " (" .. r["sar-name"] .. ")" end
        end
        s[#s + 1] = "    Resolution: " .. res_str
    end
    if ro and (r["w"] ~= ro["dw"] or r["h"] ~= ro["dh"]) then
        if ro["dw"] and ro["dh"] then
            s[#s + 1] = "    Output Resolution: " .. ro["dw"] .. "x" .. ro["dh"]
        end
    end
    -- Pixel format
    local pf = r["hw-pixelformat"] or r["pixelformat"]
    if pf then
        local pf_str = "    Format: " .. pf
        if r["colorlevels"] then pf_str = pf_str .. "  Levels: " .. r["colorlevels"] end
        if r["chroma-location"] and r["chroma-location"] ~= "unknown" then
            pf_str = pf_str .. "  Chroma Loc: " .. r["chroma-location"]
        end
        s[#s + 1] = pf_str
    end
    -- Color
    if r["colormatrix"] then
        s[#s + 1] = "    Colormatrix: " .. r["colormatrix"]
    end
    if r["primaries"] then
        local prim_str = r["primaries"]
        if r["prim-red-x"] then
            prim_str = prim_str .. string.format(" [%.3f %.3f, %.3f %.3f, %.3f %.3f, %.3f %.3f]",
                r["prim-red-x"] or 0, r["prim-red-y"] or 0,
                r["prim-green-x"] or 0, r["prim-green-y"] or 0,
                r["prim-blue-x"] or 0, r["prim-blue-y"] or 0,
                r["prim-white-x"] or 0, r["prim-white-y"] or 0)
        end
        s[#s + 1] = "    Primaries: " .. prim_str
    end
    if r["gamma"] then
        s[#s + 1] = "    Transfer: " .. r["gamma"]
    end
    -- HDR (output)
    if ro then
        local function has(val, target)
            return val and math.abs(val - target) > 1e-4
        end
        local has_dml = has(ro["min-luma"], 0.203) or has(ro["max-luma"], 203)
        local has_cll = ro["max-cll"] and ro["max-cll"] > 0
        local has_fall = ro["max-fall"] and ro["max-fall"] > 0
        if has_dml or has_cll or has_fall then
            if has_dml then
                ro["min-luma"] = ro["min-luma"] <= 1e-6 and 0 or ro["min-luma"]
                s[#s + 1] = string.format("    Mastering Display: %.2g / %.0f cd/m²",
                    ro["min-luma"], ro["max-luma"])
            end
            if has_cll then
                s[#s + 1] = string.format("    MaxCLL: %.0f cd/m²", ro["max-cll"])
            end
            if has_fall then
                s[#s + 1] = "    MaxFALL: " .. ro["max-fall"] .. " cd/m²"
            end
        end
    end
    append_property(s, "video-bitrate", "Bitrate:")
    -- Video filters
    local filters = mp.get_property_native("vf", {})
    if #filters > 0 then
        local names = {}
        for _, f in ipairs(filters) do
            local n = f.name
            if f.enabled ~= nil and not f.enabled then n = n .. " (disabled)" end
            if f.label then n = "@" .. f.label .. ": " .. n end
            names[#names + 1] = n
        end
        s[#s + 1] = "    Filters: " .. table.concat(names, ", ")
    end
end

local function add_audio(s)
    local r = mp.get_property_native("audio-params")
    local ro = mp.get_property_native("audio-out-params") or r
    r = r or ro
    if not r then return end

    local merge = function(a, b)
        if not a then return b or "N/A" end
        if not b then return a end
        return (a == b) and a or (a .. " -> " .. b)
    end

    s[#s + 1] = ""
    s[#s + 1] = "Audio:"
    local track = mp.get_property_native("current-tracks/audio")
    if track then
        local desc = track["codec-desc"] or ""
        local profile = track["codec-profile"] or ""
        local line = "    " .. desc
        if profile ~= "" then line = line .. " [" .. profile .. "]" end
        if track["codec"] ~= track["decoder"] then
            line = line .. " [" .. (track["decoder"] or "") .. "]"
        end
        s[#s + 1] = line
    end
    local ao = mp.get_property("current-ao", "")
    if ao ~= "" then
        local ao_line = "    AO: " .. ao
        local dev = mp.get_property("audio-device", "")
        if dev ~= "" then ao_line = ao_line .. "  Device: " .. dev end
        s[#s + 1] = ao_line
    end
    local vol = mp.get_property_number("ao-volume")
    if vol then
        local mute = mp.get_property_native("ao-mute") and " (Muted)" or ""
        s[#s + 1] = "    AO Volume: " .. vol .. "%" .. mute
    end
    local delay = mp.get_property_number("audio-delay", 0)
    if math.abs(delay) > 1e-6 then
        s[#s + 1] = "    A-V delay: " .. mp.get_property_osd("audio-delay")
    end
    -- Channels
    local ch = merge(r["channel-count"], ro and ro["channel-count"])
    if ch then s[#s + 1] = "    Channels: " .. ch end
    -- Format
    local fmt = merge(r["format"], ro and ro["format"])
    if fmt then s[#s + 1] = "    Format: " .. fmt end
    -- Sample rate
    local sr = merge(r["samplerate"], ro and ro["samplerate"])
    if sr then s[#s + 1] = "    Sample Rate: " .. sr .. " Hz" end
    append_property(s, "audio-bitrate", "Bitrate:")
    -- Audio filters
    local filters = mp.get_property_native("af", {})
    if #filters > 0 then
        local names = {}
        for _, f in ipairs(filters) do
            local n = f.name
            if f.enabled ~= nil and not f.enabled then n = n .. " (disabled)" end
            if f.label then n = "@" .. f.label .. ": " .. n end
            names[#names + 1] = n
        end
        s[#s + 1] = "    Filters: " .. table.concat(names, ", ")
    end
end

local function dump_info()
    local path = mp.get_property("path", "")
    if path == "" then
        mp.osd_message("No file loaded")
        return
    end

    -- Get video directory
    local dir = mp.get_property("working-directory", "")
    local filepath = path
    if not path:match("^[A-Za-z]:\\") and not path:match("^/") then
        filepath = dir .. "/" .. path
    end
    local video_dir = filepath:match("(.*[/\\])") or ""
    local filename = filepath:match("([^/\\]+)$") or "unknown"
    local basename = filename:match("(.+)%..+$") or filename
    local out_path = video_dir .. basename .. "_info.txt"

    -- Collect info using the same structure as stats.lua page 1
    local s = {}
    s[#s + 1] = string.rep("-", 60)
    s[#s + 1] = "mpv Stats - " .. mp.get_property_osd("media-title", filename)
    s[#s + 1] = string.rep("-", 60)

    add_file(s)
    add_display(s)
    add_video(s)
    add_audio(s)

    s[#s + 1] = ""
    s[#s + 1] = string.rep("-", 60)

    -- Write to file
    local content = table.concat(s, "\n")
    local f = io.open(out_path, "w")
    if f then
        f:write(content)
        f:close()
        mp.osd_message("Info saved: " .. out_path, 3)
        mp.msg.info("Info saved to: " .. out_path)
    else
        mp.osd_message("Failed to write: " .. out_path, 3)
        mp.msg.error("Failed to write to: " .. out_path)
    end
end

mp.add_key_binding("Ctrl+i", "dump-info", dump_info)
