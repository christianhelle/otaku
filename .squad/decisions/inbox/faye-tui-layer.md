# Decision: TUI/App Layer Implementation

**Author:** Faye  
**Date:** 2025  
**Status:** Implemented

## Summary

Full TUI and application layer implemented in Zig 0.15.2 using stdlib only (no external TUI libraries). Build and tests pass.

## Decisions Made

### 1. Writer passed as `*Io.Writer` (pointer), not value

**Decision:** All render functions accept `anytype` at definition but receive `*std.io.Writer` at callsites. The `render()` method in `App` creates `var w = fw.interface` and passes `&w` to sub-renders.

**Rationale:** In Zig 0.15, `Writer.print/writeAll/writeByte` take `*Writer` (mutable self). Function parameters are immutable, so passing Writer by value causes auto-borrow to `*const Writer` → compile error. Passing a pointer sidesteps this cleanly.

### 2. `ArrayListUnmanaged` instead of `ArrayList`

**Decision:** `AppState.chapter_selections` and `download_jobs` are `std.ArrayListUnmanaged(T) = .{}`.

**Rationale:** `std.ArrayList(T).init(allocator)` was removed in Zig 0.15. `ArrayListUnmanaged` uses `.{}` for default init and takes allocator explicitly on each operation. This is also slightly more flexible (AppState doesn't need to store the allocator).

### 3. Absolute cursor positioning in widgets

**Decision:** Every widget's `render()` method positions itself using `\x1b[row;colH` escape codes based on its `Rect`. No intermediate buffers or compositing layer.

**Rationale:** Simplest approach. Avoids needing a screen buffer diff/patch system. Performance is fine for 80x24 terminals; single 65 536-byte render buffer per frame.

### 4. Cross-platform raw mode via comptime branching

**Decision:** `Terminal` struct uses `if (builtin.os.tag == .windows) u32 else void` for platform-specific saved state fields. `enableRawMode` uses `comptime if` to dispatch to Win32 or POSIX code.

**Rationale:** Avoids runtime overhead and keeps platform code clearly separated. Windows needs `ENABLE_VIRTUAL_TERMINAL_INPUT` + `ENABLE_VIRTUAL_TERMINAL_PROCESSING` for ANSI sequences. POSIX uses `tcgetattr`/`tcsetattr`.

### 5. Action stubs ready for Jet's network layer

**Decision:** `actions.zig`'s `executeAction` handles all actions with stub implementations (status messages, screen navigation). Real HTTP calls left for Jet to wire in.

**Rationale:** Allows the TUI to compile and navigate screens without any network dependency. Clean handoff point.

## Files Changed

- `src/tui/terminal.zig` — Full implementation
- `src/tui/layout.zig` — Full implementation
- `src/tui/widgets/list.zig` — Full implementation
- `src/tui/widgets/detail.zig` — Full implementation
- `src/tui/widgets/statusbar.zig` — Full implementation
- `src/tui/widgets/progress.zig` — Full implementation
- `src/tui/widgets/table.zig` — Minimal (compiles)
- `src/tui/widgets/modal.zig` — Minimal (compiles)
- `src/app/state.zig` — Full implementation
- `src/app/router.zig` — Full implementation
- `src/app/app.zig` — Full implementation
- `src/app/actions.zig` — Stubbed, ready for Jet
- `src/main.zig` — Wired `.tui` command to `App.run()`
