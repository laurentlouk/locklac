# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**lockLac** is a macOS menu bar app (pure Swift) that locks your machine with a fullscreen dark overlay, traps mouse and keyboard globally, and only unlocks with the correct password. Background processes (AI training, builds, servers) continue running unaffected. The goal is to prevent physical access while long-running CPU tasks execute.

### Key Behaviors
- Menu bar agent (`NSStatusItem`) with Lock / Change Password / Quit
- On lock: fullscreen borderless overlay on all screens with blur + dark tint + centered password field
- All input intercepted via `CGEvent` tap — Cmd+Tab, Cmd+Space, Mission Control, Force Quit, everything blocked
- Mouse confined to overlay, cannot escape
- Password stored as argon2id hash in `~/.locklac/config.json`
- SSH kill switch: `locklac --unlock` or `kill $(pgrep locklac)` from remote session (Unix domain socket at `/tmp/locklac.sock`)
- Stays locked indefinitely until correct password or remote kill

## Build & Run

```sh
swift build                          # debug build
swift build -c release               # optimized build
swift run locklac                   # run the app
swift test                           # run all tests
swift test --filter <TestName>       # run a single test
swiftlint                            # lint (if SwiftLint installed)
swift package resolve                # resolve dependencies
```

Xcode: open `Package.swift`, build with Cmd+B, run with Cmd+R.

## Architecture

Swift Package with an executable target (`locklac`) and a library target (`LockLacCore`).

```
lockLac/
├── Package.swift
├── Sources/
│   ├── LockLacCore/          # library — testable logic
│   │   ├── EventTap.swift     # CGEvent tap: intercept all mouse + keyboard
│   │   ├── OverlayWindow.swift# NSWindow (screenSaver+1, borderless, all screens)
│   │   ├── PasswordStore.swift# argon2id hash read/write from ~/.locklac/config.json
│   │   ├── LockController.swift# state machine: idle → locked → unlocking
│   │   └── SocketServer.swift # Unix domain socket for SSH kill switch
│   └── locklac/              # executable
│       └── main.swift         # CLI args (lock, --unlock, set-password) + NSApplication setup
└── Tests/
    └── LockLacCoreTests/     # unit tests for password store, lock state, etc.
```

### Subsystems

1. **Menu bar agent** — `NSStatusItem` with lock icon. Runs as `LSUIElement` (no Dock icon). Dropdown: Lock, Change Password, Quit.
2. **Overlay window** — `NSWindow` at level `.screenSaver + 1`, `styleMask: .borderless`, covering all displays. `NSVisualEffectView` for blur. `NSSecureTextField` centered for password input.
3. **Event tap** — `CGEvent.tapCreate()` with `.maskForAllEvents`. Suppresses all input except keystrokes routed to the password field. Requires Accessibility permission.
4. **Password store** — `~/.locklac/config.json` with argon2id hash via Swift Crypto or a vendored argon2 implementation. Never stores plaintext.
5. **SSH kill switch** — Unix domain socket at `/tmp/locklac.sock`. `locklac --unlock` sends unlock command. Process kill also works (event tap dies with process).

### Lock Flow

```
Lock triggered (menu bar click or `locklac lock`)
  → Spawn overlay NSWindow on all screens
  → Activate CGEvent tap (suppress all input)
  → Warp mouse to center of primary screen
  → Focus NSSecureTextField
  → Keystroke → password check (argon2id verify)
    → Wrong: shake animation + "Incorrect password"
    → Correct: remove overlay, release event tap, resume normal
```

## Platform Requirements

- **macOS 13+ (Ventura)** — uses modern AppKit and Swift concurrency
- **Accessibility permission** required (System Settings → Privacy & Security → Accessibility)
- Swift 5.9+ / Xcode 15+
- App runs as `LSUIElement` — no Dock icon, menu bar only

## Conventions

- Pure Swift — no Objective-C bridging headers unless absolutely unavoidable
- Testable logic lives in `LockLacCore` library target; `locklac` executable is thin
- Password hashing: never store plaintext. Use argon2id.
- All `CGEvent` / CoreGraphics interop confined to `EventTap.swift` — don't scatter unsafe system calls
- Errors: use Swift's typed throws where possible; `Result` types for async operations
- UI: AppKit only (no SwiftUI) — we need precise control over window level, input handling, and event suppression
