# Faye — History

## Core Context

**Project:** otaku — terminal-based manga browser and downloader  
**Language:** Zig (0.15.2)  
**User:** Christian Helle  
**Build:** `zig build` | **Test:** `zig build test`  
**Stack:** Zig, terminal UI (TUI), HTTP client, manga scraping  
**Sources:** MangaFox/FanFox and other manga websites  
**Repo:** C:\projects\christianhelle\otaku  

**Team:**
- Spike — Lead (architecture, reviews)
- Jet — Systems Dev (HTTP, scraping)
- Faye (me) — TUI Dev
- Ed — Tester

**Key files (src/):** main.zig, cli.zig, tui.zig, browser.zig

## Learnings

### TUI Layer Implementation (2025)

**Files implemented:**
- `src/tui/terminal.zig` — Cross-platform raw mode (Windows: GetConsoleMode/SetConsoleMode + VT processing; POSIX: tcgetattr/tcsetattr). `readKey()` parses ANSI escape sequences for arrow keys.
- `src/tui/layout.zig` — `Rect` struct with `inner`, `splitHorizontal`, `splitVertical`, `splitThreePane`; `threePane()` (20/50/30% split) and `twoPane()` helpers.
- `src/tui/widgets/list.zig` — `ListWidget`: scrollable list with box borders (`┌┐└┘│─`), selection highlight (`\x1b[7m`), UTF-8-safe truncation.
- `src/tui/widgets/detail.zig` — `DetailWidget`: manga metadata panel with word-wrapped summary.
- `src/tui/widgets/statusbar.zig` — `StatusBar`: blue background (`\x1b[44m`), screen name, item count, key hints.
- `src/tui/widgets/progress.zig` — `ProgressBar`: `█`/`░` block characters.
- `src/tui/widgets/table.zig` — Minimal `TableWidget` (renders box border).
- `src/tui/widgets/modal.zig` — Minimal `ModalWidget` (double-line border `╔╗╚╝`).
- `src/app/state.zig` — `AppState` with screen history stack for `back()`, `ArrayListUnmanaged` for chapter_selections and download_jobs.
- `src/app/router.zig` — `handleKey()` dispatches to per-screen handlers; returns `Action` union.
- `src/app/app.zig` — `App` struct with `run()` event loop (render → readKey → action → repeat); 9 screen render functions.
- `src/app/actions.zig` — `executeAction()` stubs with status messages; ready for Jet's network layer.

**Zig 0.15.2 API notes learned:**
- `std.io.Writer.print/writeAll/writeByte` all take `*Writer` (mutable pointer). Passing Writer by value as `anytype` means function params are immutable → auto-borrow gives `*const Writer` → compile error. Solution: pass `*Writer` (i.e., `&w`) throughout.
- `std.ArrayList(T).init(allocator)` is GONE in 0.15. Use `std.ArrayListUnmanaged(T) = .{}` with allocator passed per-operation.
- `std.fs.File.stdout().writer(&buf)` returns a buffered writer; `.interface` is `std.io.Writer` (value). Declare it as `var` to get a mutable reference.
- Windows raw mode: set `ENABLE_VIRTUAL_TERMINAL_INPUT` on stdin + `ENABLE_VIRTUAL_TERMINAL_PROCESSING` on stdout for ANSI escape sequences.
- POSIX raw mode: `std.posix.termios` bitfields; `std.posix.V.MIN/TIME` via `@intFromEnum`.
- Windows console size: `std.os.windows.kernel32.GetConsoleScreenBufferInfo` with `CONSOLE_SCREEN_BUFFER_INFO.srWindow`.
- Conditional field types: `field: if (builtin.os.tag == .windows) u32 else void` works correctly; inactive branches not evaluated.
- **Windows stdout after raw mode:** On Windows, after `SetConsoleMode` is called in `enableRawMode()`, the stdout handle captured at init time becomes invalid for buffered writes. Solution: call `std.fs.File.stdout()` freshly in `render()` on Windows to get a valid handle. POSIX systems don't have this issue and can use the cached handle.

**Architecture:** widgets render with absolute cursor positioning (`\x1b[row;colH`) so each widget is self-contained. All render functions take `anytype` writer (`*Io.Writer` at callsites). Single 65 536-byte render buffer per frame, flushed at end.

### Writer Interface Bug Fix (2025-01-30)

**Root cause:** In Zig 0.15.2, `File.writer(&buf)` returns a buffered writer struct whose `.interface` field (type `std.io.Writer`) contains an internal context pointer that refers back to the parent writer. Copying `fw.interface` into a new variable creates a struct where the context pointer still points to the original `fw`, but the vtable's flush/drain functions operate on the copy's fields → mismatch → `INVALID_HANDLE` error on Windows.

**Fix:** Do NOT copy `.interface`. Use `var fw = file.writer(&buf)` and pass `&fw.interface` (pointer to the interface field) to render functions. The `anytype` parameters in widgets work with `*std.io.Writer` and dereference automatically for method calls like `writer.print(...)`.

**Key takeaway:** Zig writer interfaces contain internal pointers — treat them as non-copyable. Always use the writer in place, or pass pointers to it.
