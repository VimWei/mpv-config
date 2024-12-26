# Vimel's mpv portable_config

Following scripts are completely independent.

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

## srt-resegment.lua

* Function:
    - Resegment srt by synchronize plain text with whisper's word-level timestamps JSON
* Hotkey:
    - input.conf: Ctrl+r script-binding srt_resegment
* ref:
    - https://github.com/VimWei/WhisperTranscriber
    - WhisperTranscriber and python version of srt-resegment

## srt-to-word-level-json.lua
* Function:
    - Convert YouTube auto-generated SRT to JSON with word-level timestamps.
    - Calculate word-level timestamps using character length as a basis.
* Hotkey:
    - input.conf: Ctrl+e script-binding srt_to_word_level_json
* ref:
    - srt-resegment.lua: resegment srt by synchronize plain text with JSON

## chapter-converter.lua

* Function:
    - Converts chapter format between YouTube and mpv.
    - YouTube Chapter: "videoname.chapter" (e.g., "00:10 chapter title").
    - mpv Chapter: "videoname.ext.ffmetadata" (FFmpeg metadata standard).
* Hotkey customize:
    - Ctrl+y       script-binding   youtube-to-mpv
    - Ctrl+Alt+y   script-binding   mpv-to-youtube
* Ref:
    - loading/editing/adding/removing/saving/baking chapters
    - https://github.com/mar04/chapters_for_mpv
