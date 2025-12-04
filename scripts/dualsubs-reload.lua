-- dualsubs-reload.lua
-- src: https://github.com/VimWei/mpv-config
-- Function:
    -- Monitor external subtitle updates and automatically reload
    -- without changing the current subtitle display track

local utils = require 'mp.utils'

local CHECK_INTERVAL = 5  -- 增加到5秒
local last_check_time = 0
local timer = nil
local subs = {}
local last_track_list = nil

function log(message)
    mp.msg.info(message)
    -- mp.osd_message(message, 3)
end

function update_external_subs()
    log("---- Updating external subtitles ----")
    local tracks = mp.get_property_native("track-list")
    local new_subs = {}
    local seen_paths = {}
    local external_subs_count = 0
    local video_path = mp.get_property("path")
    local primary_sid = mp.get_property_number("sid")
    local secondary_sid = mp.get_property_number("secondary-sid")

    if not video_path then
        log("Video path is nil")
        return
    end

    local video_dir = utils.split_path(video_path)

    for _, track in ipairs(tracks) do
        if track.type == "sub" and track.external then
            local sub_filename = track["external-filename"] or track.title or "Unknown"
            -- external-filename might be a full path or relative path
            local full_path = sub_filename
            if not utils.file_info(full_path) then
                -- If not a full path, try relative to video directory
                full_path = utils.join_path(video_dir, sub_filename)
            end
            if not seen_paths[full_path] then
                local status = "none"
                if track.id == primary_sid then
                    status = "primary"
                elseif track.id == secondary_sid then
                    status = "secondary"
                end

                local sub_info = utils.file_info(full_path)
                table.insert(new_subs, {
                    path = full_path,
                    filename = sub_filename,
                    id = track.id,
                    lang = track.lang or "unknown",
                    last_modified = sub_info and sub_info.mtime or nil,
                    status = status
                })
                seen_paths[full_path] = true
                external_subs_count = external_subs_count + 1
                log(string.format("Found external subtitle %d: %s (ID: %s, Lang: %s, Status: %s)",
                    external_subs_count, sub_filename, track.id, track.lang or "unknown", status))
            end
        end
    end

    subs = new_subs
    log(string.format("Total external subtitles found: %d", external_subs_count))
end

function has_track_list_changed(new_track_list)
    if not last_track_list then
        last_track_list = new_track_list
        return true
    end

    if #last_track_list ~= #new_track_list then
        last_track_list = new_track_list
        return true
    end

    for i, track in ipairs(new_track_list) do
        local last_track = last_track_list[i]
        if track.type ~= last_track.type or
           track.id ~= last_track.id or
           track.selected ~= last_track.selected or
           (track.external and track["external-filename"] ~= last_track["external-filename"]) then
            last_track_list = new_track_list
            return true
        end
    end

    return false
end

function check_sub_update()
    -- log("---- Checking subtitles for updates ----")
    for i = #subs, 1, -1 do
        local sub = subs[i]
        local sub_info = utils.file_info(sub.path)
        if sub_info then
            if sub_info.mtime ~= sub.last_modified then
                log(string.format("==== %s changed at %s ====", sub.filename, os.date("%Y-%m-%d %H:%M:%S", sub_info.mtime)))
                sub.last_modified = sub_info.mtime
                reload_subtitle(sub)
                update_external_subs()
            end
        else
            log(string.format("Failed to get file info for: %s", sub.filename))
            table.remove(subs, i)
        end
    end
end

-- 获取当前选中的主字幕和副字幕
function get_selected_subtitles()
    local tracks = mp.get_property_native("track-list")
    local primary_sub, secondary_sub = nil, nil
    local primary_sid = mp.get_property_number("sid")
    local secondary_sid = mp.get_property_number("secondary-sid")

    -- mp.msg.info("Total tracks: " .. #tracks)
    for i, track in ipairs(tracks) do
        if track.type == "sub" then
            if track.id == primary_sid then
                primary_sub = track
                -- mp.msg.info(string.format("Primary subtitle: track %d, id=%s, lang=%s, selected=%s",
                --                       i, track.id, track.lang or "undefined", tostring(track.selected)))
            elseif track.id == secondary_sid then
                secondary_sub = track
                -- mp.msg.info(string.format("Secondary subtitle: track %d, id=%s, lang=%s, selected=%s",
                --                       i, track.id, track.lang or "undefined", tostring(track.selected)))
            end
        end
    end

    return primary_sub, secondary_sub
end

function reload_subtitle(found_sub)

    -- 1. 获取当前primary sub和secondary sub信息
    local primary_sub, secondary_sub = get_selected_subtitles()
    local original_primary_sub_id, original_secondary_sub_id
    local original_primary_sub_filename, original_secondary_sub_filename

    if primary_sub then
        original_primary_sub_id = primary_sub.id
        original_primary_sub_filename = primary_sub["external-filename"] or primary_sub.title or "Unknown"
        -- mp.msg.info("Original Primary subtitle ID: " .. original_primary_sub_id)
        -- mp.msg.info("Original Primary subtitle filename: " .. original_primary_sub_filename)
    else
        -- mp.msg.info("No original primary subtitle selected")
    end

    if secondary_sub then
        original_secondary_sub_id = secondary_sub.id
        original_secondary_sub_filename = secondary_sub["external-filename"] or secondary_sub.title or "Unknown"
        -- mp.msg.info("Original Secondary subtitle ID: " .. original_secondary_sub_id)
        -- mp.msg.info("Original Secondary subtitle filename: " .. original_secondary_sub_filename)
    else
        -- mp.msg.info("No original secondary subtitle selected")
    end

    -- 2. 重新加载字幕
    log(string.format("Reloading subtitle: %s ...", found_sub.filename))
    if found_sub then
        mp.commandv("sub-reload", found_sub.id)

        -- 3. 更新字幕选择
        -- a. 获取更新后的轨道列表
        local updated_tracks = mp.get_property_native("track-list")
        local new_sub_id = nil

        -- b. 查找新加载的字幕轨道
        for _, track in ipairs(updated_tracks) do
            if track.type == "sub" and track.external then
                local track_filename = track["external-filename"] or track.title or ""
                -- Normalize track path for comparison
                local track_path = track_filename
                if track_filename and not utils.file_info(track_path) then
                    local video_path = mp.get_property("path")
                    if video_path then
                        local video_dir = utils.split_path(video_path)
                        track_path = utils.join_path(video_dir, track_filename)
                    end
                end
                log(string.format("Comparing track path: %s with found_sub path: %s", track_path, found_sub.path))
                if track_path == found_sub.path or track_filename == found_sub.filename then
                    new_sub_id = track.id
                    log(string.format("Found new_sub_id: %s", new_sub_id))
                    break
                end
            end
        end

        if not new_sub_id then
            log("Failed to find new subtitle ID")
            return
        end

        -- c. 检查新加载的字幕是否匹配原主字幕或次字幕
        if found_sub.filename == original_primary_sub_filename then
            -- 如果是主字幕，重新设置以确保字幕正确显示
            mp.set_property("sid", "no")
            mp.set_property("secondary-sid", "no")
            if new_sub_id then
                mp.set_property_number("sid", new_sub_id)
            end
            if original_secondary_sub_id then
                mp.set_property_number("secondary-sid", original_secondary_sub_id)
            end
            log("Reloaded subtitle is the primary subtitle, updated primary subtitle")
        elseif found_sub.filename == original_secondary_sub_filename then
            -- 如果是次字幕，重新设置主字幕和次字幕
            mp.set_property("sid", "no")
            mp.set_property("secondary-sid", "no")
            if original_primary_sub_id then
                mp.set_property_number("sid", original_primary_sub_id)
            end
            if new_sub_id then
                mp.set_property_number("secondary-sid", new_sub_id)
            end
            log("Reloaded subtitle is the secondary subtitle, updated secondary subtitle")
        else
            -- 如果既不是主字幕也不是次字幕，重置为原来的设置
            mp.set_property("sid", "no")
            mp.set_property("secondary-sid", "no")
            if original_primary_sub_id then
                mp.set_property_number("sid", original_primary_sub_id)
            end
            if original_secondary_sub_id then
                mp.set_property_number("secondary-sid", original_secondary_sub_id)
            end
            log("Reloaded subtitle is neither primary nor secondary, restored original settings")
        end

        -- d. 记录字幕重新加载完成的日志
        log(string.format("... Reloaded subtitle: %s", found_sub.path))
    else
        log(string.format("Failed to find track for subtitle: %s", found_sub.path))
    end
end

function adaptive_check_sub_update()
    local current_time = os.time()
    if current_time - last_check_time >= CHECK_INTERVAL then
        check_sub_update()
        last_check_time = current_time
    end
end

mp.register_event("file-loaded", function()
    log("File loaded, initializing subtitle watch")
    update_external_subs()
    if timer then
        timer:kill()
    end
    timer = mp.add_periodic_timer(1, adaptive_check_sub_update)
end)

mp.observe_property("track-list", "native", function(name, value)
    if has_track_list_changed(value) then
        log("Track list changed, updating external subtitles")
        update_external_subs()
    end
end)
