# Decision: Phase 1 Foundation Architecture

**Date:** 2025-07-14  
**Author:** Spike (Lead)  
**Status:** Accepted

## Context
Setting up the project foundation for otaku — a Zig 0.15.2 terminal manga browser for Fanfox. Starting from default `zig init` scaffolding.

## Decisions

### 1. Application-only build (no library export)
Removed the `addModule("otaku", ...)` and dual-module pattern from build.zig. otaku is an application, not a library. Single root at `src/main.zig` with relative `@import` paths.

### 2. Domain types in `src/domain/manga.zig` as canonical source
All core types (MangaTitle, Chapter, CategoryFeed, DownloadJob, etc.) live in manga.zig. category.zig and download.zig re-export from it for ergonomic imports. Avoids circular dependencies.

### 3. CLI follows argiope Options/parseArgs pattern
Command enum + Options struct with `pub const defaults`. Manual arg parsing with while loop and index increment. No external CLI library — keeps dependencies at zero.

### 4. Chapter ordering uses float comparison
`parseChapterNumber()` converts strings like "5.5", "v2/c10" to f64 for ordering. Simple and handles all known Fanfox chapter number formats. Can be extended later if needed.

### 5. Module compile test as build gate
`test "imports compile"` in main.zig imports every submodule. This catches missing files, syntax errors, and import cycles at build time without needing integration tests yet.

### 6. Placeholder files use minimal valid Zig
Every placeholder is `const std = @import("std"); // TODO: implement <name>`. Ensures `zig build` and `zig build test` succeed with the full directory structure in place.

## Consequences
- Zero external dependencies at this stage
- All 47 source files compile and pass tests
- CLI skeleton handles all planned commands with "not yet implemented" stubs
- Foundation is ready for Jet (HTTP/scraping), Faye (TUI), and Ed (tests) to build on
