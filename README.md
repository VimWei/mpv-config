# Vimel's mpv portable_config

Following scripts are completely independent.

## touch.lua

* Function: Touch control support for mpv via RDP.
    - Tap gestures: Left 20% → sub-seek -1 or seek -5; Center 60% → play/pause; Right 20% → sub-seek +1 or seek +5.
    - Swipe gestures: Horizontal drag → seek (proportional to duration); Vertical drag left half → playback speed; Vertical drag right half → volume.

## dump-info.lua

* Function: Dump file info (same as pressing I) to a text file next to the video.
* Hotkey: Ctrl + I

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

## sub-pos-toggle.lua

* Function: Toggle primary and secondary subtitle positions between bottom and top.
* Hotkey: Alt + t
* Related: Alt + r / Alt + R to adjust secondary subtitle position up/down.

## cycle-profiles.lua

* Function: Cycle through window size/position profiles (autofit-max, autofit-large, autofit-normal, autofit-small, left-2/3, right-2/3).
* Source: https://github.com/VimWei/mpv-config

## context_menu.lua

* Function: Default context menu of mpv (bundled since mpv 0.4.1).

## chapter-converter.lua

* Function:
    - Converts chapter format between YouTube and mpv.
    - YouTube Chapter: "videoname.ext.chapter" (e.g., "00:10 chapter title").
    - mpv Chapter: "videoname.ext.ffmetadata" (FFmpeg metadata standard).
* Hotkey customize:
    - Ctrl+y       script-binding   youtube-to-mpv
    - Ctrl+Alt+y   script-binding   mpv-to-youtube
* Ref:
    - loading/editing/adding/removing/saving/baking chapters
    - https://github.com/mar04/chapters_for_mpv

## @python/mpvchapter/mpvchapter.py

* Function:
    - Automatically create video chapters by detecting silent audio segments.
    - Uses FFmpeg for audio processing.
* Features:
    - Smart thresholding: Auto-adjusts silence detection to fit the video's audio characteristics.
    - Highly Customizable: A `config.json` file allows for detailed adjustments.
    - Batch Processing: Capable of handling multiple video files in one go.
* Usage:
    - Run the script via `python python/mpvchapter/mpvchapter.py`.
* Ref:
    - The script's own README at `python/mpvchapter/README.md` provides more details.

## @python/video_reencoder/video_reencoder.py

* Function: Batch re-encode video files using FFmpeg.

## Archive Script

### srt-resegment.lua

* Function:
    - Resegment srt by synchronize plain text with whisper's word-level timestamps JSON
* Hotkey:
    - input.conf: Ctrl+r script-binding srt_resegment
* ref:
    - https://github.com/VimWei/WhisperTranscriber
    - https://github.com/VimWei/WhisperXTranscriber

### srt-to-word-level-json.lua
* Function:
    - Convert YouTube auto-generated SRT to JSON with word-level timestamps.
    - Calculate word-level timestamps using character length as a basis.
* Hotkey:
    - input.conf: Ctrl+e script-binding srt_to_word_level_json
* ref:
    - srt-resegment.lua: resegment srt by synchronize plain text with JSON
