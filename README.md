# Otaku

A high-performance desktop manga reader written in [Zig](https://ziglang.org/).

[![CI](https://github.com/christianhelle/otaku/actions/workflows/ci.yml/badge.svg)](https://github.com/christianhelle/otaku/actions/workflows/ci.yml)
[![Release](https://github.com/christianhelle/otaku/actions/workflows/release.yml/badge.svg)](https://github.com/christianhelle/otaku/actions/workflows/release.yml)

## Features

- Crawls well-known manga websites (MangaDex API) for titles, chapters, and pages
- Compact binary database for local persistence of crawled data
- Immediate-mode UI designed for maximum rendering performance
- Fast startup and low memory footprint
- Cross-platform: Linux, macOS, Windows
- Single static binary — no runtime dependencies

## Architecture

```
main.zig  →  database.zig  ←→  manga.zig (types + serialization)
    ↓              ↑
 ui.zig      crawler.zig (MangaDex API)
```

| Module | Responsibility |
|---|---|
| `manga.zig` | Core data types and binary serialization |
| `database.zig` | File-based persistence layer (`~/.config/otaku/`) |
| `crawler.zig` | MangaDex API crawler with lightweight JSON scanner |
| `ui.zig` | UI state machine and navigation logic |
| `main.zig` | Entry point; wires database, crawler, and UI together |

## Build from source

Requires [Zig 0.15.2+](https://ziglang.org/download/):

```sh
zig build -Doptimize=ReleaseFast
```

The binary is at `zig-out/bin/otaku`.

## Usage

```sh
# Run otaku
zig build run

# Run tests
zig build test
```

### Snap

```sh
sudo snap install otaku
```

### Download from GitHub Releases

Pre-built binaries for Linux (x86_64, aarch64), macOS (x86_64, aarch64), and Windows (x86_64) are available on the [Releases](https://github.com/christianhelle/otaku/releases) page.

## License

MIT
