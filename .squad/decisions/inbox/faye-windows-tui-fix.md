# Windows TUI Crash Fix — Fresh Stdout Handle After Raw Mode

**Date:** 2025-01-22  
**Author:** Faye (TUI Dev)  
**Status:** Implemented  

## Problem

Running `otaku` (no args, TUI mode) crashed on Windows with:
```
error: WriteFailed
windows.zig:701: .INVALID_HANDLE => return error.NotOpenForWriting
```

The crash occurred in `App.render()` at `w.flush()` when flushing the buffered writer to stdout.

## Root Cause

On Windows, calling `SetConsoleMode` in `Terminal.enableRawMode()` modifies the console mode flags on the stdout handle. While the handle remains valid for immediate small writes (like in `hideCursor`, `showCursor`), it becomes INVALID for buffered writes that accumulate data and then flush.

The `Terminal` struct captured stdout at init time (before raw mode), and `App.render()` used this cached handle. After raw mode was enabled, Windows treated the buffered write+flush pattern on this handle as invalid.

## Solution

On Windows only, get a fresh stdout handle at the start of each `render()` call by calling `std.fs.File.stdout()`:

```zig
const stdout_file = if (comptime @import("builtin").os.tag == .windows)
    std.fs.File.stdout()
else
    self.terminal.stdout;
var fw = stdout_file.writer(&buf);
```

POSIX systems (Linux, macOS) are unaffected and continue using the cached `self.terminal.stdout`.

## Why This Works

`std.fs.File.stdout()` returns a new `File` struct pointing to the current stdout handle from the OS. On Windows, this ensures we get a handle that's valid for buffered writes in the current console mode state (raw mode with VT processing enabled).

The handle value itself doesn't change, but the OS's internal view of what operations are valid on it does change after `SetConsoleMode`. Re-querying ensures we have a handle the OS considers valid for buffered I/O.

## Testing

- `zig build` — passes  
- `zig build test` — passes  
- Launching `otaku.exe` and letting it run for 3 seconds — process stays alive (previously crashed immediately)  

## Alternatives Considered

1. **Use unbuffered writes** — Zig 0.15.2 has no unbuffered writer API; `.writer(file, buffer)` always requires a buffer.  
2. **Reduce buffer size** — Tried 8KB instead of 64KB; didn't fix the issue.  
3. **Re-enter raw mode before each render** — Unnecessary overhead and doesn't address the root cause.  
4. **Cache a "post-raw-mode" stdout** — Would require restructuring init/lifecycle; the fresh-get approach is simpler.  

## Future Work

If other Windows console handle issues arise, consider wrapping all Windows console writes in a helper that always gets a fresh stdout handle. For now, the render function is the only place where large buffered writes occur, so this targeted fix is sufficient.

## Related Files

- `src/app/app.zig` — render() function (lines 72-98)  
- `src/tui/terminal.zig` — Terminal.init(), enableRawMode()  
- `.squad/agents/faye/history.md` — documented as learning  
