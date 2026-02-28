# otaku

[![Build](https://github.com/christianhelle/otaku/actions/workflows/build.yml/badge.svg)](https://github.com/christianhelle/otaku/actions/workflows/build.yml)
[![Tests](https://github.com/christianhelle/otaku/actions/workflows/test.yml/badge.svg)](https://github.com/christianhelle/otaku/actions/workflows/test.yml)

**Desktop Manga Reader** – a high-performance manga reader built with [Zig](https://ziglang.org/) and [SDL2](https://www.libsdl.org/).

## Features

- 📚 **Personal library** – browse your manga collection, stored locally in SQLite
- 🔍 **Search** – query manga sources (MangaDex) directly from the app
- 📖 **Reader** – chapter-by-chapter reading with page progress tracking
- ⚡ **Immediate mode UI** – game-loop architecture for maximum UI performance
- 💾 **Offline-first** – crawled metadata and chapters are persisted locally
- 🔒 **Privacy** – no telemetry, no accounts required

## Screenshots

> _Run `zig build run` on a desktop with a display to see the application._

## Building

### Prerequisites

- **Zig 0.15.2** ([download](https://ziglang.org/download/))
- **libSDL2** + **libSDL2_ttf**
- **libsqlite3**

```sh
# Ubuntu / Debian
sudo apt-get install libsdl2-dev libsdl2-ttf-dev libsqlite3-dev
```

### Build & Run

```sh
# Build (outputs to zig-out/bin/otaku)
zig build

# Run unit tests
zig build test

# Run the application
zig build run
```

### Release build

```sh
zig build -Doptimize=ReleaseFast
```

## Architecture

```
src/
├── main.zig      – Entry point, game loop, screen rendering
├── root.zig      – Library root
├── manga.zig     – Core data types (Manga, Chapter, Page)
├── database.zig  – SQLite persistence layer
├── crawler.zig   – HTTP web crawler + HTML parser
└── ui.zig        – SDL2 immediate mode UI system
```

The UI is modelled after **Dear ImGui** – each frame the application state
drives the entire UI render with no retained widget state. This game-engine
approach delivers consistent 60 FPS performance even with large manga libraries.

## Supported Manga Sources

| Source        | Search | Chapters | Pages |
|---------------|--------|----------|-------|
| MangaDex      | ✅      | ✅        | ✅     |
| MangaKakalot  | 🚧      | 🚧        | 🚧     |
| MangaSee      | 🚧      | 🚧        | 🚧     |

> ✅ = implemented · 🚧 = planned

## Ubuntu Snap

Otaku is published to the Ubuntu App Store as a snap:

```sh
sudo snap install otaku
```

_(snap publishing coming soon)_

## Contributing

See [.github/copilot-instructions.md](.github/copilot-instructions.md) for
architecture details and coding conventions.

## License

MIT
