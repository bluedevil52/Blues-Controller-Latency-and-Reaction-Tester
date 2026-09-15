# Reaction Lab

For the standalone download, extract the ZIP and double-click **BluesControllerLatencyAndReactionTester.exe**. Godot does not need to be installed. Close and reopen an already running copy to load updates. For source development, open project.godot in Godot and press F5; the local **Launch Reaction Lab** shortcut also runs the development version.

## Run a benchmark

1. Enter a benchmark name and choose 1–200 scored trials.
2. Select your controller, keyboard, or mouse. Press an input and watch the indicator below the selector to confirm the device.
3. Start. Release all buttons, wait on red, and press any button when the screen turns green.
4. Results save automatically. The newest run is selected in the leaderboard, even when its rank puts it on a later page.

No binding is needed. Controllers accept all button events exposed by Godot, including D-pad and stick clicks. Analog triggers count when they cross 50%, with release below 20% to suppress jitter. Stick movement is ignored. Keyboard mode accepts any key except Escape. Mouse mode accepts physical buttons, not wheel motion. Keyboard and mouse events are grouped by type; this backend does not distinguish multiple physical keyboards or mice. Controllers are individually selected.

A press on red displays **Don't cheat!** and retries that trial without including the early response in the average. Ten-second timeouts also retry. The app waits for every held button to be released before the next trial. Every successful reaction is retained without trimming, including unusually fast or slow responses.

Escape, loss of focus, or disconnection of the selected controller cancels an unfinished run. Unrelated controller disconnects do not cancel it. Partial runs are not saved. If saving fails, keep the app open and use Retry save.

## Leaderboard and trash

The interface has no scrolling. Arrow buttons page through five results at a time and ten individual trial times at a time. The window supports 880×624 and larger, scaling the interface from its 1100×780 design size. Hover over truncated names or device details for the full text and metadata.

Click a row's trash icon to remove that one benchmark from the leaderboard. **Undo trash** restores the most recently trashed result in the current session. This is reversible soft deletion: the JSON file moves into `results/trash`; it is not permanently deleted. Older trashed results remain there across restarts and can be restored manually by moving their JSON files back into results. A filename collision causes an error rather than overwriting either file.

Use Open results folder to open:
`%LOCALAPPDATA%\LatencyTester\results`

The app stores its settings in `%LOCALAPPDATA%\LatencyTester\settings.cfg`. It remembers the trial count, fullscreen option and VSync option between launches. When moving from the older development version, the app makes a one-time copy of existing results and the `trash` folder from `%APPDATA%\Godot\app_userdata\Latency Tester\results`. The original files stay where they are, and a matching filename is never overwritten. New results use the LocalAppData folder shown above.

Each completed run has a separate JSON file. Duplicate names remain separate entries. The files contain individual times, mean/median/best/worst/standard deviation, early-press/timeout counts, device metadata, the input used for each scored trial, display settings, engine version and frame interval statistics. Older results from the binding-based version still load.

Starter and pre-revision files are preserved under backups. The project's general no-deletion rule and the scoped leaderboard trash behavior are documented in AGENTS.md.

## Timing and comparisons

Scores measure human reaction plus the software/display/input path, not isolated controller hardware latency. Timing uses a monotonic microsecond clock from immediately before drawing green (RenderingServer.frame_pre_draw) to the input callback. That is a software render boundary, not the instant pixels become visible. Clock resolution does not equal measurement accuracy.

Input accumulation is disabled. Responses use _input, not the physics loop. Rendering is uncapped; VSync defaults off during testing. VSync may add delay; turning it off may introduce tearing. OS scheduling, desktop composition, drivers, frame scheduling and display scanout still affect results. Frame interval statistics provide context, not calibration. The menu uses VSync to reduce idle load.

Use the same monitor, refresh rate, posture, button and display settings. Any button works, but using the same button across comparisons improves consistency. Trigger thresholds add a different physical actuation point. Warm up and alternate controllers across multiple runs with similar trial counts. Small differences may just be human variation. The leaderboard includes all runs; inspect settings before comparing them.

## Device support and diagnostics

Godot 4.7 uses SDL3 controller input on Windows. XInput and legacy controllers supported by that backend work without manual binding. Arbitrary USB HID devices and OS-reserved buttons are not guaranteed. Keyboard/mouse-emulating USB buttons work in the corresponding mode. Remapping software may expose a virtual device.

Available vendor/product IDs and XInput identification appear in the panel; hover for full engine metadata including GUID. Missing IDs may appear as zero.

References:
- https://docs.godotengine.org/en/stable/tutorials/inputs/controllers_gamepads_joysticks.html
- https://docs.godotengine.org/en/stable/classes/class_input.html
- https://docs.godotengine.org/en/stable/classes/class_renderingserver.html

## Validation and review

54 automated regression checks pass, covering input filtering and multiple buttons, trigger thresholds/noise, early presses, held inputs, timing transitions, saving/reopening, paging through 200 trials, latest-run selection, trash/undo, path validation and failure preservation. Tests use separate files under user://test_artifacts. Real benchmark files were not altered during tests.

Run with the installed Godot executable:
`Godot_v4.7.2-stable_win64.exe --headless --path . --script res://tests/test_runner.gd`

The visual review covers empty/populated states, long names, 200 trials, smaller windows, save-error controls, early-press feedback and the green cue. UI boundary checks also pass. Input tests use synthetic events; actual controller presses and broad hardware compatibility still need hands-on testing.

See REVIEW.md for the review history, including the later three-round UI pass. CODE_GUIDE.md explains the now-commented code for beginners.


## Latest UI and QA update

Checkbox padding now stays identical across normal, hover, checked-hover and disabled states. The benchmark starts red immediately, stays red during release/wait/feedback, and turns green only for the scored response. Undo selects the restored result. Refresh rates are formatted to one decimal place. Keyboard focus is visible on action buttons.

Final verification also includes 27 rendered UI/integration checks covering actual GUI event routing, fullscreen red start, checkbox hover, a complete saved run, paging, trash/undo and minimum-window layout. This uses simulated inputs, not a physical button-press rig.


## Wording conventions

Headings and labels use sentence case: capitalize the first word and proper names, rather than every word or all capitals. Product names and acronyms retain their usual spelling, such as Reaction Lab, VSync, USB and XInput.

- Benchmark: the complete named session.
- Trial: one reaction attempt; early presses and timeouts repeat it.
- Result: one saved benchmark entry in the leaderboard.
- Average: arithmetic mean of completed reaction times.
- Median: middle reaction time.
- Fastest: shortest reaction time.
- Variation (SD): standard deviation; lower values indicate more consistent reaction times.

The UI uses milliseconds (ms) for reaction times and hertz (Hz) for refresh rates. Internal JSON keys such as mean_ms, best_ms and run_id are unchanged for compatibility with existing results. Device-specific instructions say key, mouse button or controller button as appropriate.

## Check the selected device

The small LED below the device information glows green and shows Input detected when the selected device produces a supported button, key or trigger press. A quick tap stays visible for 180 milliseconds; holding an input keeps it lit. Switching devices resets the indicator. Other controllers, stick movement and mouse scrolling do not activate it. Checking inputs on this screen does not start or save a benchmark.

The polling-rate display has been removed. Vendor/product IDs and other available device information remain.

## Age reference panel

The top-right panel shows published average simple visual reaction times: ages 18–25, 243.1 ms; ages 45–60, 283.9 ms; ages 61–80, 296.1 ms. Each group contained 50 participants. Source: Deary, Liewald and Nissan (2011), Table 1, DLS mean: https://doi.org/10.3758/s13428-010-0024-1

These are study averages from a keyboard task with a different display setup, not controller latency or direct targets for this app. The study did not include ages 26–44; the app does not estimate missing age groups. The source is documented here to keep the on-screen card compact.
