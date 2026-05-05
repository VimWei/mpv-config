-- sub-pos-toggle.lua
-- src: https://github.com/VimWei/mpv-config
-- Function: Toggle primary and secondary subtitle positions between bottom and top
-- Hotkey: Alt+t

local is_top = false
local saved_sub_pos = nil
local saved_secondary_sub_pos = nil

function toggle_sub_pos()
    if is_top then
        if saved_sub_pos then
            mp.set_property_number("sub-pos", saved_sub_pos)
        end
        if saved_secondary_sub_pos then
            mp.set_property_number("secondary-sub-pos", saved_secondary_sub_pos)
        end
        is_top = false
        mp.osd_message(string.format("字幕位置：底部 (主:%d 副:%d)",
            mp.get_property_number("sub-pos"),
            mp.get_property_number("secondary-sub-pos")))
    else
        saved_sub_pos = mp.get_property_number("sub-pos")
        saved_secondary_sub_pos = mp.get_property_number("secondary-sub-pos")
        mp.set_property_number("sub-pos", 15)
        mp.set_property_number("secondary-sub-pos", 0)
        is_top = true
        mp.osd_message(string.format("字幕位置：顶部 (主:15 副:0) ← 原:主%d 副%d",
            saved_sub_pos, saved_secondary_sub_pos))
    end
end

mp.add_key_binding("Alt+t", "sub-pos-toggle", toggle_sub_pos)
