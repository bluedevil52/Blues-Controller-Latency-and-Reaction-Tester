# Blue's Controller Latency and Reaction Tester

A small Windows app for comparing controller reaction times. Pick a device, wait for green, and press any button. The in-app interface is called Reaction Lab.

## Download and run — no coding required

1. Open **Releases** on the right of this GitHub page.
2. Download **Blues-Controller-Latency-and-Reaction-Tester-v1.01-windows-x64.zip** from **Assets**. The automatically generated "Source code" downloads are for editing the project.
3. Right-click the downloaded ZIP and choose **Extract All**.
4. Open the extracted folder and double-click **BluesControllerLatencyAndReactionTester.exe**.

No Godot installation, editor, installer, or internet connection is needed to run the app. This build is for 64-bit Windows PCs. It is unsigned, so Windows may show an unknown-publisher warning; check that you downloaded it from this repository's release.

## What it does

- Named benchmarks with 1–200 completed trials and an average at the end.
- Controller selection with an input-check LED. No button binding required.
- Keyboard and mouse modes for compatible USB input devices.
- Red-to-green cue; early presses show "Don't cheat!" and repeat the trial.
- Local leaderboard, individual trial times, and reversible trash with Undo.
- Fullscreen and VSync options, plus a small age-reference panel.

This measures **your reaction time plus display and input delays**, not isolated USB/controller latency. Use the same display and settings when comparing controllers. Device support depends on the input events exposed by Godot; arbitrary USB devices are not guaranteed.

## Where your results go

Results stay on your PC in:

```text
%APPDATA%\Godot\app_userdata\Latency Tester\results
```

Paste that path into File Explorer's address bar, or click **Open results folder** in the app. Existing results from the development version remain available. Trashing a result moves its file into a `trash` subfolder; it does not permanently delete it. Results and local backups are not included in this repository or the download.

Read [START HERE.md](START%20HERE.md) for the full user guide and [CODE_GUIDE.md](CODE_GUIDE.md) for a beginner's tour of the code.

## Edit the app

1. Install the standard (non-.NET) **Godot 4.7.2** from [godotengine.org](https://godotengine.org/download/archive/4.7.2-stable/).
2. Download this repository's source ZIP, extract it, and import `project.godot` in Godot.
3. Press **F5** to run it. Start reading `main.gd` and `benchmark_store.gd` to understand how it works.

## Build your own Windows executable

In Godot, use **Editor → Manage Export Templates** to install the matching **4.7.2** templates. Then choose **Project → Export → Windows Desktop → Export Project**, turn off **Export With Debug**, and choose an output filename. The preset embeds the app data inside the executable.

Or run the included PowerShell build script, replacing the example with your Godot executable's real path:

```powershell
.\scripts\build-windows.ps1 -GodotPath 'C:\path\to\Godot_v4.7.2-stable_win64.exe'
```

Each build goes into a new timestamped folder under `release`, so earlier builds are retained. It includes the standalone executable, user guide and engine license notices.

## Development checks

Run these from the project folder with your Godot executable (replace `godot` with its path if needed):

```text
godot --headless --path . --script res://tests/test_runner.gd
godot --path . --script res://tests/ui_interaction_qa.gd
godot --path . --script res://tests/input_indicator_qa.gd
```

The tests use synthetic inputs and isolated test results. They do not establish physical controller latency or universal hardware compatibility. UI tests briefly open app windows and move the pointer.

## Credits

Built with Godot. [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt) includes its license and dependency notices. The age references are documented in [START HERE.md](START%20HERE.md).
