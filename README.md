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

## chapter-converter.lua

* Function:
    - Converts timestamps from YouTube format to MPV chapter format (FFmpeg metadata).
    - Input: Plain text file named "videoname.chapter", for example:
        - 01:12:34.567 timestamp supports HH:MM:SS.mmm
        - 01:12:34 or only HH:MM:SS
        - 12:34.567 or only MM:SS.mmm
        - 12:34 or only MM:SS
        - 34.567 or only SS.mmm
        - 34 or only SS
    - Output: "videoname.ext.ffmetadata"

* Hotkey:
    - input.conf: Ctrl+y script-binding chapter-converter
* Ref:
    - loading/editing/adding/removing/saving/baking chapters
    - https://github.com/mar04/chapters_for_mpv
