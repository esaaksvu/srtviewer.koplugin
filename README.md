# SRT Viewer for KOReader

A native, e-ink optimized `.srt` subtitle player built as a custom plugin for KOReader. 

Whether you are studying languages, analyzing film pacing, or just reading subtitles like a script, this plugin allows you to load and "play" subtitle files directly on your e-reader.

## Features

* **E-Ink Optimized "Smart Ticker":** Unlike standard video players, this plugin minimizes screen flashing and battery drain by only redrawing the screen when the text changes or the visible timestamp ticks.
* **Smart Seeking:** Jump to any timestamp using a forgiving input system. Supports `HH:MM:SS`, `MM:SS`, `HH.MM.SS`, `MM.SS`, or raw seconds (e.g., typing `120` or `02.00` both jump exactly 2 minutes in).
* **Progress Tracking:** Automatically remembers exactly where you paused or closed a file. Reopening the same `.srt` file later will instantly jump back to your saved timestamp.
* **Rotation Support:** Seamlessly swap between Portrait and Landscape modes on the fly without breaking the user interface or losing your place.
* **Persistent File Explorer:** Remembers the last folder you opened, so you don't have to navigate from your home directory every time you load a new file.

## Installation

1. Connect your e-reader to your computer via USB.
2. Navigate to your device's KOReader plugins directory:
   * Standard path: `koreader/plugins/`
3. Create a new folder named exactly: `srtviewer.koplugin`
4. Inside that new folder, place your `main.lua` script (and this `README.md` if you wish).
5. Eject your device and completely restart KOReader.

## Usage

1. Open KOReader's main top menu.
2. Navigate to the **Tools** tab.
3. Tap **SRT Player**.
4. Use the file chooser to locate and select your `.srt` file.
5. Tap **Play** to start the timer, or **Seek** to jump to a specific moment.

## Technical Details & Limitations

* **No Audio/Video:** This is purely a text parser and timer. It does not play media files.
* **HTML Tags:** Currently, the parser reads raw text. If your `.srt` file contains heavy HTML formatting (like `<i>` or `<b>` tags), those tags will be displayed as raw text on the screen.
* **File Encoding:** Ensure your `.srt` files are saved with UTF-8 encoding so special characters and non-English languages render correctly using KOReader's native fonts.

## Changelog

* **v1.0.0** - Initial release featuring smart parsing, e-ink optimized playback, progress saving, and rotation support.

## License

This project is licensed under the MIT License.
