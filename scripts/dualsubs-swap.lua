-- dualsubs-swap.lua
-- 通过快捷键 Alt+u 快速交换主次字幕的位置

-- 获取当前选中的主字幕和副字幕
function get_selected_subtitles()
    local tracks = mp.get_property_native("track-list")
    local primary_sub, secondary_sub = nil, nil
    local primary_sid = mp.get_property_number("sid")
    local secondary_sid = mp.get_property_number("secondary-sid")

    mp.msg.info("Total tracks: " .. #tracks)
    for i, track in ipairs(tracks) do
        if track.type == "sub" then
            if track.id == primary_sid then
                primary_sub = track
                mp.msg.info(string.format("Primary subtitle: track %d, id=%s, lang=%s, selected=%s",
                                      i, track.id, track.lang or "undefined", tostring(track.selected)))
            elseif track.id == secondary_sid then
                secondary_sub = track
                mp.msg.info(string.format("Secondary subtitle: track %d, id=%s, lang=%s, selected=%s",
                                      i, track.id, track.lang or "undefined", tostring(track.selected)))
            end
        end
    end

    return primary_sub, secondary_sub
end

-- 交换字幕位置的函数

function swap_subtitles()
    local primary_sub, secondary_sub = get_selected_subtitles()

    if primary_sub and secondary_sub then
        -- 两个字幕都存在，交换它们
        mp.msg.info(string.format("Swapping subtitles: Primary ID%s <-> Secondary ID%s",
                                  primary_sub.id, secondary_sub.id))
        -- 先取消选择两个字幕
        mp.set_property("sid", "no")
        mp.set_property("secondary-sid", "no")
        -- 然后重新选择字幕，但交换它们的位置
        mp.set_property("sid", secondary_sub.id)
        mp.set_property("secondary-sid", primary_sub.id)
        mp.osd_message(string.format("已交换字幕：主字幕 ID%s <-> 副字幕 ID%s",
                                     secondary_sub.id, primary_sub.id))
    elseif primary_sub and not secondary_sub then
        -- 只有主字幕，将其移到副字幕
        mp.msg.info(string.format("Moving primary subtitle to secondary"))
        mp.set_property("sid", "no")
        mp.set_property("secondary-sid", primary_sub.id)
        mp.osd_message(string.format("已移动：主字幕 ID%s -> 副字幕", primary_sub.id))
    elseif not primary_sub and secondary_sub then
        -- 只有副字幕，将其移到主字幕
        mp.msg.info(string.format("Moving secondary subtitle to primary"))
        mp.set_property("secondary-sid", "no")
        mp.set_property("sid", secondary_sub.id)
        mp.osd_message(string.format("已移动：副字幕 ID%s -> 主字幕", secondary_sub.id))
    else
        -- 没有任何字幕
        mp.msg.info("No subtitles available for swapping")
        mp.osd_message("没有可交换的字幕轨道")
    end

end

-- 绑定快捷键 Alt+u 到交换字幕函数
mp.add_key_binding("Alt+u", "swap_subtitles", swap_subtitles)
