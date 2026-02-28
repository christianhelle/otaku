/// SDL2-based immediate mode UI system for Otaku.
/// Each frame the entire UI is re-rendered from scratch based on current state,
/// following the immediate mode GUI (IMGUI) paradigm used by game UIs.
const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});

// ---- Colour theme ----

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub fn toSDL(self: Color) c.SDL_Color {
        return .{ .r = self.r, .g = self.g, .b = self.b, .a = self.a };
    }
};

pub const Theme = struct {
    background: Color = .{ .r = 18, .g = 18, .b = 18 },
    surface: Color = .{ .r = 30, .g = 30, .b = 30 },
    surface_hover: Color = .{ .r = 45, .g = 45, .b = 45 },
    primary: Color = .{ .r = 255, .g = 64, .b = 64 },
    primary_hover: Color = .{ .r = 255, .g = 100, .b = 100 },
    text: Color = .{ .r = 230, .g = 230, .b = 230 },
    text_muted: Color = .{ .r = 140, .g = 140, .b = 140 },
    border: Color = .{ .r = 60, .g = 60, .b = 60 },
    accent: Color = .{ .r = 255, .g = 200, .b = 50 },
    input_bg: Color = .{ .r = 25, .g = 25, .b = 25 },
    scrollbar: Color = .{ .r = 80, .g = 80, .b = 80 },
};

pub const default_theme = Theme{};

// ---- Rect ----

pub const Rect = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,

    pub fn contains(self: Rect, px: i32, py: i32) bool {
        return px >= self.x and px < self.x + self.w and
            py >= self.y and py < self.y + self.h;
    }

    pub fn toSDL(self: Rect) c.SDL_Rect {
        return .{ .x = self.x, .y = self.y, .w = self.w, .h = self.h };
    }

    pub fn inflate(self: Rect, amount: i32) Rect {
        return .{
            .x = self.x - amount,
            .y = self.y - amount,
            .w = self.w + amount * 2,
            .h = self.h + amount * 2,
        };
    }
};

// ---- Input state ----

pub const MouseButton = enum { left, right, middle };

pub const InputState = struct {
    mouse_x: i32 = 0,
    mouse_y: i32 = 0,
    mouse_left_down: bool = false,
    mouse_left_clicked: bool = false,
    mouse_right_clicked: bool = false,
    mouse_wheel_y: i32 = 0,
    keys_pressed: [512]bool = [_]bool{false} ** 512,
    text_input: [32]u8 = [_]u8{0} ** 32,
    text_input_len: usize = 0,
    backspace_pressed: bool = false,
    enter_pressed: bool = false,
    escape_pressed: bool = false,

    pub fn reset(self: *InputState) void {
        self.mouse_left_clicked = false;
        self.mouse_right_clicked = false;
        self.mouse_wheel_y = 0;
        self.keys_pressed = [_]bool{false} ** 512;
        self.text_input = [_]u8{0} ** 32;
        self.text_input_len = 0;
        self.backspace_pressed = false;
        self.enter_pressed = false;
        self.escape_pressed = false;
    }
};

// ---- UI context ----

pub const UiError = error{
    SdlInitFailed,
    WindowCreateFailed,
    RendererCreateFailed,
    TtfInitFailed,
    FontLoadFailed,
    OutOfMemory,
};

pub const FontSize = enum { small, normal, large, title };

pub const Ui = struct {
    allocator: std.mem.Allocator,
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    font_small: ?*c.TTF_Font = null,
    font_normal: ?*c.TTF_Font = null,
    font_large: ?*c.TTF_Font = null,
    font_title: ?*c.TTF_Font = null,
    theme: Theme,
    input: InputState,
    width: i32,
    height: i32,
    should_quit: bool = false,
    active_input_id: u32 = 0,
    frame_time_ms: u32 = 0,

    /// Initialise SDL2, create a window and renderer.
    pub fn init(allocator: std.mem.Allocator, title: [*:0]const u8, width: i32, height: i32) UiError!Ui {
        if (c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS) != 0) return UiError.SdlInitFailed;
        if (c.TTF_Init() != 0) {
            c.SDL_Quit();
            return UiError.TtfInitFailed;
        }

        const window = c.SDL_CreateWindow(
            title,
            c.SDL_WINDOWPOS_CENTERED,
            c.SDL_WINDOWPOS_CENTERED,
            width,
            height,
            c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_RESIZABLE,
        ) orelse {
            c.TTF_Quit();
            c.SDL_Quit();
            return UiError.WindowCreateFailed;
        };

        const renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC) orelse
            c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_SOFTWARE) orelse {
            c.SDL_DestroyWindow(window);
            c.TTF_Quit();
            c.SDL_Quit();
            return UiError.RendererCreateFailed;
        };

        _ = c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND);

        return Ui{
            .allocator = allocator,
            .window = window,
            .renderer = renderer,
            .theme = default_theme,
            .input = .{},
            .width = width,
            .height = height,
        };
    }

    /// Load fonts from a font file path.
    pub fn loadFonts(self: *Ui, font_path: [*:0]const u8) UiError!void {
        self.font_small = c.TTF_OpenFont(font_path, 12) orelse return UiError.FontLoadFailed;
        self.font_normal = c.TTF_OpenFont(font_path, 15) orelse return UiError.FontLoadFailed;
        self.font_large = c.TTF_OpenFont(font_path, 20) orelse return UiError.FontLoadFailed;
        self.font_title = c.TTF_OpenFont(font_path, 28) orelse return UiError.FontLoadFailed;
    }

    /// Clean up all SDL resources.
    pub fn deinit(self: *Ui) void {
        if (self.font_small) |f| c.TTF_CloseFont(f);
        if (self.font_normal) |f| c.TTF_CloseFont(f);
        if (self.font_large) |f| c.TTF_CloseFont(f);
        if (self.font_title) |f| c.TTF_CloseFont(f);
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
        c.TTF_Quit();
        c.SDL_Quit();
    }

    /// Poll SDL events. Returns true if the app should continue running.
    pub fn pollEvents(self: *Ui) bool {
        self.input.reset();
        const start = c.SDL_GetTicks();

        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => self.should_quit = true,
                c.SDL_WINDOWEVENT => {
                    if (event.window.event == c.SDL_WINDOWEVENT_RESIZED) {
                        self.width = event.window.data1;
                        self.height = event.window.data2;
                    }
                },
                c.SDL_MOUSEMOTION => {
                    self.input.mouse_x = event.motion.x;
                    self.input.mouse_y = event.motion.y;
                },
                c.SDL_MOUSEBUTTONDOWN => {
                    if (event.button.button == c.SDL_BUTTON_LEFT) self.input.mouse_left_down = true;
                },
                c.SDL_MOUSEBUTTONUP => {
                    if (event.button.button == c.SDL_BUTTON_LEFT) {
                        self.input.mouse_left_down = false;
                        self.input.mouse_left_clicked = true;
                    }
                    if (event.button.button == c.SDL_BUTTON_RIGHT) self.input.mouse_right_clicked = true;
                },
                c.SDL_MOUSEWHEEL => {
                    self.input.mouse_wheel_y = event.wheel.y;
                },
                c.SDL_KEYDOWN => {
                    const scancode: usize = @intCast(event.key.keysym.scancode);
                    if (scancode < self.input.keys_pressed.len) {
                        self.input.keys_pressed[scancode] = true;
                    }
                    if (event.key.keysym.sym == c.SDLK_BACKSPACE) self.input.backspace_pressed = true;
                    if (event.key.keysym.sym == c.SDLK_RETURN or event.key.keysym.sym == c.SDLK_KP_ENTER) self.input.enter_pressed = true;
                    if (event.key.keysym.sym == c.SDLK_ESCAPE) self.input.escape_pressed = true;
                },
                c.SDL_TEXTINPUT => {
                    const text = &event.text.text;
                    var i: usize = 0;
                    while (i < text.len and text[i] != 0) : (i += 1) {
                        if (self.input.text_input_len < self.input.text_input.len) {
                            self.input.text_input[self.input.text_input_len] = @bitCast(text[i]);
                            self.input.text_input_len += 1;
                        }
                    }
                },
                else => {},
            }
        }

        self.frame_time_ms = c.SDL_GetTicks() - start;
        return !self.should_quit;
    }

    /// Begin rendering a new frame.
    pub fn beginFrame(self: *Ui) void {
        const bg = self.theme.background;
        _ = c.SDL_SetRenderDrawColor(self.renderer, bg.r, bg.g, bg.b, bg.a);
        _ = c.SDL_RenderClear(self.renderer);
    }

    /// End frame and present to screen.
    pub fn endFrame(self: *Ui) void {
        c.SDL_RenderPresent(self.renderer);
    }

    // ---- Drawing primitives ----

    pub fn drawRect(self: *Ui, rect: Rect, color: Color) void {
        _ = c.SDL_SetRenderDrawColor(self.renderer, color.r, color.g, color.b, color.a);
        var r = rect.toSDL();
        _ = c.SDL_RenderFillRect(self.renderer, &r);
    }

    pub fn drawRectOutline(self: *Ui, rect: Rect, color: Color) void {
        _ = c.SDL_SetRenderDrawColor(self.renderer, color.r, color.g, color.b, color.a);
        var r = rect.toSDL();
        _ = c.SDL_RenderDrawRect(self.renderer, &r);
    }

    pub fn drawLine(self: *Ui, x1: i32, y1: i32, x2: i32, y2: i32, color: Color) void {
        _ = c.SDL_SetRenderDrawColor(self.renderer, color.r, color.g, color.b, color.a);
        _ = c.SDL_RenderDrawLine(self.renderer, x1, y1, x2, y2);
    }

    /// Render text at position. Returns text width or 0 on failure.
    pub fn drawText(self: *Ui, text: []const u8, x: i32, y: i32, color: Color, size: FontSize) i32 {
        const font = self.getFont(size) orelse return 0;
        if (text.len == 0) return 0;

        // Need null-terminated string for TTF
        var buf: [1024]u8 = undefined;
        if (text.len >= buf.len) return 0;
        @memcpy(buf[0..text.len], text);
        buf[text.len] = 0;

        const surface = c.TTF_RenderUTF8_Blended(font, &buf, color.toSDL()) orelse return 0;
        defer c.SDL_FreeSurface(surface);
        const texture = c.SDL_CreateTextureFromSurface(self.renderer, surface) orelse return 0;
        defer c.SDL_DestroyTexture(texture);

        const dst = c.SDL_Rect{
            .x = x,
            .y = y,
            .w = surface.*.w,
            .h = surface.*.h,
        };
        _ = c.SDL_RenderCopy(self.renderer, texture, null, &dst);
        return surface.*.w;
    }

    /// Render clipped text (will not overflow the rect).
    pub fn drawTextClipped(self: *Ui, text: []const u8, rect: Rect, color: Color, size: FontSize) void {
        const font = self.getFont(size) orelse return;
        if (text.len == 0) return;

        var buf: [1024]u8 = undefined;
        if (text.len >= buf.len) return;
        @memcpy(buf[0..text.len], text);
        buf[text.len] = 0;

        const surface = c.TTF_RenderUTF8_Blended(font, &buf, color.toSDL()) orelse return;
        defer c.SDL_FreeSurface(surface);
        const texture = c.SDL_CreateTextureFromSurface(self.renderer, surface) orelse return;
        defer c.SDL_DestroyTexture(texture);

        const clip_w = @min(surface.*.w, rect.w);
        const src = c.SDL_Rect{ .x = 0, .y = 0, .w = clip_w, .h = surface.*.h };
        const dst = c.SDL_Rect{ .x = rect.x, .y = rect.y, .w = clip_w, .h = surface.*.h };
        _ = c.SDL_RenderCopy(self.renderer, texture, &src, &dst);
    }

    fn getFont(self: *Ui, size: FontSize) ?*c.TTF_Font {
        return switch (size) {
            .small => self.font_small,
            .normal => self.font_normal,
            .large => self.font_large,
            .title => self.font_title,
        };
    }

    pub fn textSize(self: *Ui, text: []const u8, size: FontSize) struct { w: i32, h: i32 } {
        const font = self.getFont(size) orelse return .{ .w = 0, .h = 0 };
        var buf: [1024]u8 = undefined;
        if (text.len == 0 or text.len >= buf.len) return .{ .w = 0, .h = 0 };
        @memcpy(buf[0..text.len], text);
        buf[text.len] = 0;
        var w: c_int = 0;
        var h: c_int = 0;
        _ = c.TTF_SizeUTF8(font, &buf, &w, &h);
        return .{ .w = @intCast(w), .h = @intCast(h) };
    }

    // ---- Immediate mode widgets ----

    /// Render a filled button. Returns true if clicked this frame.
    pub fn button(self: *Ui, rect: Rect, btn_label: []const u8) bool {
        const hovered = rect.contains(self.input.mouse_x, self.input.mouse_y);
        const clicked = hovered and self.input.mouse_left_clicked;
        const bg = if (hovered) self.theme.primary_hover else self.theme.primary;
        self.drawRect(rect, bg);
        const ts = self.textSize(btn_label, .normal);
        const tx = rect.x + @divTrunc(rect.w - ts.w, 2);
        const ty = rect.y + @divTrunc(rect.h - ts.h, 2);
        _ = self.drawText(btn_label, tx, ty, self.theme.text, .normal);
        return clicked;
    }

    /// Render a flat button (no background unless hovered). Returns true if clicked.
    pub fn flatButton(self: *Ui, rect: Rect, btn_label: []const u8, color: Color) bool {
        const hovered = rect.contains(self.input.mouse_x, self.input.mouse_y);
        const clicked = hovered and self.input.mouse_left_clicked;
        if (hovered) self.drawRect(rect, self.theme.surface_hover);
        _ = self.drawText(btn_label, rect.x + 8, rect.y + @divTrunc(rect.h - 15, 2), color, .normal);
        return clicked;
    }

    /// Render a text label.
    pub fn label(self: *Ui, rect: Rect, text: []const u8, color: Color, size: FontSize) void {
        self.drawTextClipped(text, rect, color, size);
    }

    /// Scrollable list. item_height is the height of each row.
    /// scroll_offset is updated if the user scrolls while hovering.
    /// Returns the index clicked, or -1.
    pub fn scrollableList(
        self: *Ui,
        rect: Rect,
        items: []const []const u8,
        selected_index: i32,
        scroll_offset: *i32,
        item_height: i32,
    ) i32 {
        self.drawRect(rect, self.theme.surface);
        self.drawRectOutline(rect, self.theme.border);

        // Scroll with mouse wheel if hovered
        if (rect.contains(self.input.mouse_x, self.input.mouse_y) and self.input.mouse_wheel_y != 0) {
            scroll_offset.* -= self.input.mouse_wheel_y * item_height;
            const max_scroll = @max(0, @as(i32, @intCast(items.len)) * item_height - rect.h);
            scroll_offset.* = std.math.clamp(scroll_offset.*, 0, max_scroll);
        }

        var clicked_idx: i32 = -1;
        const start_idx = @divTrunc(scroll_offset.*, item_height);
        const visible_count = @divTrunc(rect.h, item_height) + 2;

        // Set clip rect
        var clip = rect.toSDL();
        _ = c.SDL_RenderSetClipRect(self.renderer, &clip);

        var i: i32 = start_idx;
        while (i < @as(i32, @intCast(items.len)) and i < start_idx + visible_count) : (i += 1) {
            const item_y = rect.y + i * item_height - scroll_offset.*;
            const item_rect = Rect{ .x = rect.x + 1, .y = item_y, .w = rect.w - 2, .h = item_height };

            const hovered = item_rect.contains(self.input.mouse_x, self.input.mouse_y) and
                rect.contains(self.input.mouse_x, self.input.mouse_y);

            if (i == selected_index) {
                self.drawRect(item_rect, Color{ .r = 60, .g = 30, .b = 30 });
            } else if (hovered) {
                self.drawRect(item_rect, self.theme.surface_hover);
            }

            const text_rect = Rect{ .x = item_rect.x + 8, .y = item_y + 4, .w = item_rect.w - 16, .h = item_height };
            const color = if (i == selected_index) self.theme.accent else self.theme.text;
            self.drawTextClipped(items[@intCast(i)], text_rect, color, .normal);

            if (hovered and self.input.mouse_left_clicked) {
                clicked_idx = i;
            }
        }

        // Draw scrollbar
        if (items.len > 0) {
            const total_h = @as(i32, @intCast(items.len)) * item_height;
            if (total_h > rect.h) {
                const sb_x = rect.x + rect.w - 6;
                const sb_h = @max(20, @divTrunc(rect.h * rect.h, total_h));
                const sb_y = rect.y + @divTrunc(scroll_offset.* * (rect.h - sb_h), total_h - rect.h);
                self.drawRect(Rect{ .x = sb_x, .y = sb_y, .w = 5, .h = sb_h }, self.theme.scrollbar);
            }
        }

        _ = c.SDL_RenderSetClipRect(self.renderer, null);
        return clicked_idx;
    }

    /// Single-line text input. id is a unique u32 to track focus.
    /// buffer is the text storage (caller manages), cursor_pos is updated.
    /// Returns true if Enter was pressed.
    pub fn textInput(
        self: *Ui,
        rect: Rect,
        id: u32,
        buffer: *std.ArrayList(u8),
        cursor_pos: *usize,
    ) bool {
        const focused = self.active_input_id == id;
        if (rect.contains(self.input.mouse_x, self.input.mouse_y) and self.input.mouse_left_clicked) {
            self.active_input_id = id;
        }

        const bg = if (focused) self.theme.input_bg else self.theme.surface;
        self.drawRect(rect, bg);
        self.drawRectOutline(rect, if (focused) self.theme.primary else self.theme.border);

        if (focused) {
            // Handle text input
            if (self.input.text_input_len > 0) {
                const insert = self.input.text_input[0..self.input.text_input_len];
                buffer.insertSlice(self.allocator, cursor_pos.*, insert) catch {};
                cursor_pos.* += insert.len;
            }
            if (self.input.backspace_pressed and cursor_pos.* > 0) {
                _ = buffer.orderedRemove(cursor_pos.* - 1);
                cursor_pos.* -= 1;
            }

            c.SDL_StartTextInput();
        } else {
            c.SDL_StopTextInput();
        }

        const text_rect = Rect{ .x = rect.x + 8, .y = rect.y + 4, .w = rect.w - 16, .h = rect.h };
        self.drawTextClipped(buffer.items, text_rect, self.theme.text, .normal);

        // Draw cursor
        if (focused) {
            const prefix = buffer.items[0..cursor_pos.*];
            const ts = self.textSize(prefix, .normal);
            const cx = rect.x + 8 + ts.w;
            const now = c.SDL_GetTicks();
            if (@mod(now, 1000) < 500) {
                self.drawLine(cx, rect.y + 4, cx, rect.y + rect.h - 4, self.theme.text);
            }
        }

        return focused and self.input.enter_pressed;
    }

    /// Placeholder label drawn inside an empty text box.
    pub fn textInputWithPlaceholder(
        self: *Ui,
        rect: Rect,
        id: u32,
        buffer: *std.ArrayList(u8),
        cursor_pos: *usize,
        placeholder: []const u8,
    ) bool {
        const result = self.textInput(rect, id, buffer, cursor_pos);
        if (buffer.items.len == 0 and self.active_input_id != id) {
            const text_rect = Rect{ .x = rect.x + 8, .y = rect.y + 4, .w = rect.w - 16, .h = rect.h };
            self.drawTextClipped(placeholder, text_rect, self.theme.text_muted, .normal);
        }
        return result;
    }

    /// Horizontal tab bar. Returns the index of the active tab (may be changed by click).
    pub fn tabBar(self: *Ui, rect: Rect, tabs: []const []const u8, active: i32) i32 {
        var new_active = active;
        const tab_w = @divTrunc(rect.w, @as(i32, @intCast(tabs.len)));
        for (tabs, 0..) |tab, i| {
            const tab_rect = Rect{
                .x = rect.x + @as(i32, @intCast(i)) * tab_w,
                .y = rect.y,
                .w = tab_w,
                .h = rect.h,
            };
            const is_active = i == @as(usize, @intCast(active));
            const hovered = tab_rect.contains(self.input.mouse_x, self.input.mouse_y);
            const bg: Color = if (is_active) self.theme.primary else if (hovered) self.theme.surface_hover else self.theme.surface;
            self.drawRect(tab_rect, bg);
            if (is_active) {
                self.drawLine(tab_rect.x, tab_rect.y + tab_rect.h - 2, tab_rect.x + tab_rect.w, tab_rect.y + tab_rect.h - 2, self.theme.accent);
            }
            const ts = self.textSize(tab, .normal);
            const tx = tab_rect.x + @divTrunc(tab_rect.w - ts.w, 2);
            const ty = tab_rect.y + @divTrunc(tab_rect.h - ts.h, 2);
            _ = self.drawText(tab, tx, ty, self.theme.text, .normal);

            if (hovered and self.input.mouse_left_clicked) {
                new_active = @intCast(i);
            }
        }
        return new_active;
    }

    /// Progress bar (value 0.0 to 1.0).
    pub fn progressBar(self: *Ui, rect: Rect, value: f32, color: Color) void {
        self.drawRect(rect, self.theme.surface);
        const fill_w = @as(i32, @intFromFloat(@as(f32, @floatFromInt(rect.w)) * std.math.clamp(value, 0, 1)));
        if (fill_w > 0) {
            self.drawRect(Rect{ .x = rect.x, .y = rect.y, .w = fill_w, .h = rect.h }, color);
        }
        self.drawRectOutline(rect, self.theme.border);
    }

    /// Separator line.
    pub fn separator(self: *Ui, x: i32, y: i32, width: i32) void {
        self.drawLine(x, y, x + width, y, self.theme.border);
    }

    /// Badge/chip label with colored background.
    pub fn badge(self: *Ui, x: i32, y: i32, text: []const u8, bg_color: Color) void {
        const ts = self.textSize(text, .small);
        const pad = 6;
        const badge_rect = Rect{ .x = x, .y = y, .w = ts.w + pad * 2, .h = ts.h + 4 };
        self.drawRect(badge_rect, bg_color);
        _ = self.drawText(text, x + pad, y + 2, self.theme.text, .small);
    }
};
