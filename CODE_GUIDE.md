# Reading the code as a beginner

Start with main.gd. The opening comments map the app. Godot opens main.tscn, which attaches that script to a full-window Control. The interface is built by code rather than assembled in the visual scene editor.

## A useful reading order

1. `_ready`: startup. It builds the UI, loads devices/results and connects signals.
2. `_start_run`: checks the name, captures settings, clears only the current in-memory samples, paints red and shows the trial screen.
3. `_process`: advances the run when deadlines are reached. It runs once per frame.
4. `_input`: processes presses/releases as they arrive. This is where a reaction gets recorded.
5. `_complete_run` and `_save_pending`: build a result and save it.
6. `benchmark_store.gd`: calculates statistics, reads/writes JSON and handles reversible trash.
7. `_build_ui`: read this when you want to change the layout or controls.

## The state machine

A state machine is just a variable that tells the program what is happening now.

`IDLE → RELEASE → WAIT → PENDING_GREEN → GO → FEEDBACK`

- IDLE: the menu is visible.
- RELEASE: the screen is already red. Any buttons held before starting must be released; new presses count as early.
- WAIT: still red, with a random 1.8–5 second delay.
- PENDING_GREEN: green has been requested, but its render timestamp has not been taken yet.
- GO: the green frame is being drawn. A valid press can now score.
- FEEDBACK: show the score, early-press message or timeout on red. Continue with RELEASE, or finish when enough valid trials exist.
- COMPLETE: prepare and save the finished result, then return to IDLE. A save error keeps the result in memory for Retry.

The release settling time and the random wait are separate: releasing all buttons starts a short 0.7-second settling period before the random delay.

## GDScript features used here

- `var` creates a variable. `:=` asks Godot to infer its type. `: int` explicitly declares an integer.
- `Array` holds an ordered list. `samples[0]` means the first sample, because indexes start at zero.
- `Dictionary` holds named values. `record["name"]` and `record.name` are used to access its fields.
- `if`, `elif` and `else` choose a branch. Indentation groups the statements in that branch.
- `return` ends the function immediately; an early return is useful for rejecting invalid input.
- A `Callable` is a function passed as a value. A signal such as `pressed` calls a connected function when something happens.
- `func() -> void:` inside another function is an inline function, often called a lambda.
- `duplicate()` makes a copy. It keeps a completed result independent from the arrays used for the next run.
- `%s`, `%d` and `%.1f` format text, integers and one-decimal numbers.

## Timing without blocking the app

One second is 1,000,000 microseconds. `Time.get_ticks_usec()` reads a monotonic clock: changing the PC's calendar time does not change elapsed reaction time. We subtract the green timestamp from the input timestamp and divide by 1,000 for milliseconds.

Deadlines let `_process` check whether it is time to move on. There is no blocking sleep in the app. Input can still be received while waiting. The input callback checks the timeout too, because an input might arrive before the next frame checks it.

The timestamp is taken before the green frame draws. This is not a measurement of when the monitor emits light, so clock resolution does not equal hardware-latency accuracy.

## Why held inputs are a dictionary

Suppose A and B are both held. Releasing A must not tell the app that every button is released. `held_inputs` keeps a separate entry for each held control. Releases remove only their own entry. Repeated press events cannot score twice.

A trigger produces continuous numbers, not just pressed/released events. It presses above 0.5 and releases below 0.2. The gap prevents small analog fluctuations from generating repeated presses. Stick movement is ignored.

## UI padding and the hover bug

A button has normal, hover, pressed, hover_pressed and disabled states. A StyleBox defines its background and padding. All states need matching padding or the text can move when the state changes. `_style_button` now supplies all those states explicitly. Checked and unchecked icons have identical dimensions too.

Containers position controls. VBoxContainer stacks them; HBoxContainer places them side by side. Pagination avoids needing a scrolling page. The focus outline makes keyboard navigation visible.

## Saving and preserving files

`res://` is this project. `user://` is the app's writable data folder. Each completed run gets a JSON file, and duplicate names get separate files. A failed save keeps `pending_record` in memory.

`clear()` on an Array, Dictionary or Tree clears in-memory data or UI rows. It does not delete PC files. The trash action moves only the selected result into `results/trash`; Undo moves it back. Path checks and collision checks happen before the move. No permanent-delete operation is used.

JSON parsing does not execute code. Required fields are validated; invalid optional metadata is normalized only in memory. Unreadable files remain on disk.

## Safe things to experiment with

Change `WAIT_RED`/`GO_GREEN` for colors, the timing constants for waits, or label text in `_build_ui`. Keep comments and timing descriptions consistent with any changes you make. Back up first, and do not delete earlier work.

After changing behavior, run `tests/test_runner.gd` with Godot's headless script option. `tests/ui_interaction_qa.gd` runs with the renderer and exercises real GUI routing using simulated input. It also moves the pointer to check tree buttons. Both use isolated test data rather than your real results.
