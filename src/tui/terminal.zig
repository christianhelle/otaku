const std = @import("std");
const builtin = @import("builtin");

pub const Key = enum {
    up,
    down,
    left,
    right,
    enter,
    escape,
    tab,
    backspace,
    char_q,
    char_j,
    char_k,
    char_h,
    char_l,
    char_g,
    char_s,
    char_d,
    char_a,
    char_r,
    char_b,
    char_slash,
    char_space,
    char_question,
    char_A,
    other,
};

const is_windows = builtin.os.tag == .windows;

pub const Terminal = struct {
    stdout: std.fs.File,
    stdin: std.fs.File,
    saved_termios: if (!is_windows) std.posix.termios else void,
    saved_stdin_mode: if (is_windows) u32 else void,
    saved_stdout_mode: if (is_windows) u32 else void,

    pub fn init() !Terminal {
        const stdout = std.fs.File.stdout();
        const stdin = std.fs.File.stdin();
        var term: Terminal = undefined;
        term.stdout = stdout;
        term.stdin = stdin;
        if (comptime is_windows) {
            term.saved_termios = {};
            var sin_mode: u32 = 0;
            var sout_mode: u32 = 0;
            if (std.os.windows.kernel32.GetConsoleMode(stdin.handle, &sin_mode) == 0)
                return error.ConsoleError;
            if (std.os.windows.kernel32.GetConsoleMode(stdout.handle, &sout_mode) == 0)
                return error.ConsoleError;
            term.saved_stdin_mode = sin_mode;
            term.saved_stdout_mode = sout_mode;
        } else {
            term.saved_stdin_mode = {};
            term.saved_stdout_mode = {};
            term.saved_termios = try std.posix.tcgetattr(stdin.handle);
        }
        return term;
    }

    pub fn deinit(self: *Terminal) void {
        self.disableRawMode() catch {};
        self.showCursor() catch {};
    }

    pub fn enableRawMode(self: *Terminal) !void {
        if (comptime is_windows) {
            const ENABLE_VIRTUAL_TERMINAL_INPUT: u32 = 0x0200;
            const ENABLE_EXTENDED_FLAGS: u32 = 0x0080;
            const ENABLE_VIRTUAL_TERMINAL_PROCESSING: u32 = 0x0004;
            if (std.os.windows.kernel32.SetConsoleMode(
                self.stdin.handle,
                ENABLE_VIRTUAL_TERMINAL_INPUT | ENABLE_EXTENDED_FLAGS,
            ) == 0) return error.RawModeFailed;
            if (std.os.windows.kernel32.SetConsoleMode(
                self.stdout.handle,
                self.saved_stdout_mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING,
            ) == 0) return error.RawModeFailed;
        } else {
            var raw = self.saved_termios;
            raw.lflag.ECHO = false;
            raw.lflag.ICANON = false;
            raw.lflag.ISIG = false;
            raw.lflag.IEXTEN = false;
            raw.iflag.IXON = false;
            raw.iflag.ICRNL = false;
            raw.iflag.BRKINT = false;
            raw.iflag.INPCK = false;
            raw.iflag.ISTRIP = false;
            raw.oflag.OPOST = false;
            raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
            raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;
            try std.posix.tcsetattr(self.stdin.handle, .FLUSH, raw);
        }
    }

    pub fn disableRawMode(self: *Terminal) !void {
        if (comptime is_windows) {
            _ = std.os.windows.kernel32.SetConsoleMode(self.stdin.handle, self.saved_stdin_mode);
            _ = std.os.windows.kernel32.SetConsoleMode(self.stdout.handle, self.saved_stdout_mode);
        } else {
            try std.posix.tcsetattr(self.stdin.handle, .FLUSH, self.saved_termios);
        }
    }

    pub fn getSize(self: Terminal) !struct { width: u16, height: u16 } {
        if (comptime is_windows) {
            var csbi: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
            if (std.os.windows.kernel32.GetConsoleScreenBufferInfo(self.stdout.handle, &csbi) == 0)
                return .{ .width = 80, .height = 24 };
            const w: u16 = @intCast(csbi.srWindow.Right - csbi.srWindow.Left + 1);
            const h: u16 = @intCast(csbi.srWindow.Bottom - csbi.srWindow.Top + 1);
            return .{ .width = w, .height = h };
        } else {
            var size = std.mem.zeroes(std.posix.winsize);
            const TIOCGWINSZ: u32 = switch (builtin.os.tag) {
                .macos, .ios, .tvos => 0x40087468,
                else => 0x5413,
            };
            const rc = std.posix.system.ioctl(self.stdout.handle, TIOCGWINSZ, @intFromPtr(&size));
            if (rc != 0 or size.ws_col == 0) return .{ .width = 80, .height = 24 };
            return .{ .width = size.ws_col, .height = size.ws_row };
        }
    }

    pub fn hideCursor(self: Terminal) !void {
        var buf: [16]u8 = undefined;
        var fw = self.stdout.writer(&buf);
        try fw.interface.writeAll("\x1b[?25l");
        try fw.interface.flush();
    }

    pub fn showCursor(self: Terminal) !void {
        var buf: [16]u8 = undefined;
        var fw = self.stdout.writer(&buf);
        try fw.interface.writeAll("\x1b[?25h");
        try fw.interface.flush();
    }

    pub fn clearScreen(self: Terminal) !void {
        var buf: [16]u8 = undefined;
        var fw = self.stdout.writer(&buf);
        try fw.interface.writeAll("\x1b[2J\x1b[H");
        try fw.interface.flush();
    }

    pub fn moveCursor(self: Terminal, row: u16, col: u16) !void {
        var buf: [32]u8 = undefined;
        var fw = self.stdout.writer(&buf);
        try fw.interface.print("\x1b[{d};{d}H", .{ row, col });
        try fw.interface.flush();
    }
};

pub fn readKey(file: std.fs.File) !Key {
    var b: [1]u8 = undefined;
    const n = try file.read(&b);
    if (n == 0) return .other;
    const c = b[0];
    if (c == '\x1b') {
        var seq: [2]u8 = undefined;
        const n2 = file.read(seq[0..1]) catch return .escape;
        if (n2 == 0) return .escape;
        if (seq[0] != '[' and seq[0] != 'O') return .escape;
        const n3 = file.read(seq[1..2]) catch return .escape;
        if (n3 == 0) return .escape;
        return switch (seq[1]) {
            'A' => .up,
            'B' => .down,
            'C' => .right,
            'D' => .left,
            else => .other,
        };
    }
    return switch (c) {
        '\r', '\n' => .enter,
        '\x7f', '\x08' => .backspace,
        '\t' => .tab,
        'q' => .char_q,
        'j' => .char_j,
        'k' => .char_k,
        'h' => .char_h,
        'l' => .char_l,
        'g' => .char_g,
        's' => .char_s,
        'd' => .char_d,
        'a' => .char_a,
        'A' => .char_A,
        'r' => .char_r,
        'b' => .char_b,
        '/' => .char_slash,
        ' ' => .char_space,
        '?' => .char_question,
        '\x03' => .escape,
        else => .other,
    };
}
