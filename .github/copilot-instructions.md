# Copilot Instructions for Otaku

## Project Overview
Otaku is a desktop manga reader built in **Zig 0.15** using **SDL2** for the UI layer and **SQLite** for local persistence. The UI follows an **immediate mode** pattern inspired by game engines – every frame the entire UI is re-rendered from application state.

## Architecture

```
src/
├── main.zig      – Entry point, application game loop, screen rendering
├── root.zig      – Library root (re-exports core modules)
├── manga.zig     – Core data types: Manga, Chapter, Page, MangaStatus, MangaSite
├── database.zig  – SQLite persistence layer (CRUD for manga/chapters/pages)
├── crawler.zig   – HTTP web crawler + HTML parser for manga sites
└── ui.zig        – SDL2 immediate mode UI: widgets, theme, input handling
```

## Key Design Decisions

### Immediate Mode UI
- `ui.Ui` holds the SDL2 window, renderer, fonts, and input state.
- Each call to `gui.beginFrame()` clears the screen. Widgets are drawn by calling functions like `gui.button(rect, text)` – they render themselves and return interaction results (e.g., `bool` for clicked).
- No retained widget state; everything is driven by `AppState` in `main.zig`.
- Target: 60 FPS game loop with `SDL_Delay` to cap frame rate.

### Memory Management
- All heap allocations go through `std.mem.Allocator` (typically a `GeneralPurposeAllocator` in production, `testing.allocator` in tests).
- In Zig 0.15, `std.ArrayList(T)` is unmanaged: pass the allocator to every method (`append`, `deinit`, `toOwnedSlice`, etc.).
- Structs with heap-allocated strings (`Manga`, `Chapter`, `Page`) provide `dupe(allocator)` and `free(allocator)` helpers.
- Use `errdefer` to clean up allocations on error paths.

### Database Layer (database.zig)
- Wraps the SQLite C library via `@cImport({ @cInclude("sqlite3.h"); })`.
- All queries use prepared statements to prevent SQL injection.
- The schema is created with `IF NOT EXISTS` so the database is auto-migrated on first run.
- Foreign key cascade deletes ensure referential integrity (manga → chapters → pages).

### Web Crawler (crawler.zig)
- Uses `std.http.Client` with `std.Io.Writer.Allocating` to collect response bodies.
- `HtmlParser` is a lightweight hand-rolled HTML pattern extractor (no full DOM parse).
- `parseMangaDexSearch` and `parseMangaDexChapters` use `std.json` to decode API responses.
- Sites are configured via `manga.known_sites` (a compile-time array of `MangaSite` structs).

## Coding Conventions
- All public types and functions have doc-comments (`///`).
- Error types are explicit `error{...}` sets or narrowly scoped to the module.
- Tests live at the bottom of each source file, using `std.testing.allocator` for leak detection.
- Use `defer` and `errdefer` consistently for resource cleanup.
- Avoid `@panic` in library code; return errors instead.

## Building
```sh
# Build the executable
zig build

# Run unit tests
zig build test

# Run the app (requires a display)
zig build run
```

## Dependencies
- **Zig 0.15.2** or later
- **libSDL2-dev** + **libSDL2_ttf-dev** – windowing and text rendering
- **libsqlite3-dev** – embedded database

## Adding a New Manga Source
1. Add a new `MangaSite` entry to `manga.known_sites` in `src/manga.zig`.
2. Implement a `parse<SiteName>Search` function in `src/crawler.zig` that returns `[]manga.Manga`.
3. Add a corresponding `parse<SiteName>Chapters` function.
4. Wire it up in `Crawler.searchMangaDex` (or add a new `search` method).
5. Write unit tests for both parsing functions using inline JSON fixtures.

## Testing Strategy
- `manga.zig`: Pure unit tests – no I/O, no allocator leaks.
- `database.zig`: Tests open an in-memory SQLite database (`:memory:`). Each test is independent.
- `crawler.zig`: Tests use inline JSON/HTML strings – no network calls.
- `ui.zig`: The SDL2 UI is not unit-tested (requires a display). Manual testing via `zig build run`.
