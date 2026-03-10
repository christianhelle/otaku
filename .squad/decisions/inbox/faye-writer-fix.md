# Writer Interface Copy Bug — Fixed

**Date:** 2025-01-30  
**Agent:** Faye (TUI Dev)  
**Status:** ✅ Resolved

## Problem

Running `otaku` (TUI mode) crashed with:
```
error: WriteFailed
windows.zig:701: in WriteFile
    .INVALID_HANDLE => return error.NotOpenForWriting
```

## Root Cause

In `src/app/app.zig`, the `render()` function was copying the writer interface:
```zig
var buf: [65536]u8 = undefined;
const fw = self.terminal.stdout.writer(&buf);
var w = fw.interface;   // ← PROBLEM: copies the interface struct
```

In Zig 0.15.2's Writer API, the `.interface` field contains an internal context pointer that refers back to the parent writer struct. When you copy `fw.interface` into `w`, the context pointer in `w` still points to `fw`, but the vtable's flush function operates on `w`'s fields (like `w.end`) while the drain function tries to write from `fw`'s buffer. This mismatch causes `INVALID_HANDLE` on Windows.

Compare with the working `hideCursor()`:
```zig
var fw = self.stdout.writer(&buf);
try fw.interface.writeAll("\x1b[?25l");  // uses fw.interface directly
try fw.interface.flush();                 // uses fw.interface directly
```

## Solution

**Do not copy `fw.interface`** — use it directly:

```zig
var buf: [65536]u8 = undefined;
var fw = self.terminal.stdout.writer(&buf);

try fw.interface.writeAll("\x1b[2J\x1b[H");
// ... render calls ...
try self.renderHome(&fw.interface, ...);
try fw.interface.flush();
```

Changed all render function calls from `&w` to `&fw.interface`.

Additionally, added platform-specific handling for Windows to get a fresh stdout handle after raw mode is enabled, since `SetConsoleMode` can affect handle validity for buffered writes.

## Key Insight

Zig writer interfaces contain internal pointers and are **not copyable**. Always use the writer in place, or pass pointers to it. The `anytype` parameters in widgets work correctly with `*std.io.Writer` and dereference automatically for method calls.

## Verification

- ✅ `zig build` — passed
- ✅ `zig build test` — passed
- ✅ No more crashes on Windows

## Files Changed

- `src/app/app.zig`: Fixed `render()` function to use `&fw.interface` instead of copying to `var w`
