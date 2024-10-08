mp.register_event("start-file", function()
    mp.msg.info("MPV version: " .. mp.get_property("mpv-version"))
end)
