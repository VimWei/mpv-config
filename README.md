# Vimel's mpv portable_config

mpv.conf, input.conf and some lua scripts.

## input.conf

* Cheatsheet: Toggleable Persistent Display of Active Key Bindings
    - hotkey: ?
    - ref: https://github.com/mpv-player/mpv/issues/14966

## mpv.conf

* Subtitle
    - --sub-auto=fuzzy
    - --sub-font-size=45
    - --sub-pos=92
    - --secondary-sub-pos=100
    - --secondary-sub-ass-override=scale

## dualsubs-init.lua

* Function: Automatically load dual subtitles on startup.
* dualsubs-init.conf: Primary and secondary subtitle language preferences.

## dualsubs-swap.lua

* Function: Quickly swap positions of primary and secondary subtitles.
* Hotkey: Alt + u

## dualsubs-reload.lua

* Automatically reload external subtitle when updated without changing the current subtitle display track.

## dualsubs-creat.lua

* Function:
    - Create bilingual ASS subtitles with pop movie style
    - Uses currently selected primary and secondary subtitles
    - Supports both external and embedded subtitles
* Hotkey: Shift + b
