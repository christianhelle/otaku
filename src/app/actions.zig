const std = @import("std");
const app_mod = @import("app.zig");
const App = app_mod.App;
const router = @import("router.zig");
const Action = router.Action;
const state_mod = @import("state.zig");
const Screen = state_mod.Screen;
const manga = @import("../domain/manga.zig");

pub fn executeAction(app: *App, action: Action) !void {
    switch (action) {
        .none => {},
        .quit => {
            app.running = false;
        },
        .back => {
            app.state.back();
        },
        .navigate_to => |screen| {
            app.state.navigate(screen);
        },
        .load_category => |kind| {
            app.state.loading = true;
            var buf: [64]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "Loading {s}...", .{kind.label()}) catch "Loading...";
            app.state.setStatus(msg);
            app.state.current_category = kind;
            app.state.category_selected = 0;
            app.state.navigate(.category_list);
            // Real network call wired in when Jet's layer is complete
        },
        .load_title => |url| {
            _ = url;
            app.state.loading = true;
            app.state.setStatus("Loading title...");
            app.state.navigate(.title_detail);
        },
        .load_chapters => |slug| {
            _ = slug;
            app.state.loading = true;
            app.state.setStatus("Loading chapters...");
            app.state.navigate(.chapter_list);
        },
        .download_selected => {
            app.state.setStatus("Download queued");
        },
        .download_all => {
            app.state.setStatus("All chapters queued for download");
        },
        .start_search => |query| {
            _ = query;
            app.state.setStatus("Searching...");
            app.state.navigate(.search_results);
        },
        .build_library => {
            app.state.setStatus("Building library...");
        },
        .refresh => {
            app.state.loading = true;
            app.state.setStatus("Refreshing...");
        },
    }
}
