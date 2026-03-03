# clawLock — Design Document

**Date:** 2026-03-03
**Status:** Approved

## Summary

clawLock is a macOS menu bar app (pure Swift) that locks the machine with a fullscreen dark overlay. It traps all mouse and keyboard input globally and only unlocks when the correct password is entered. Background processes continue running — the purpose is to prevent physical access while long-running CPU tasks (AI training, builds, servers) execute.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Language | Pure Swift | Native AppKit access, no FFI complexity |
| UI approach | Fullscreen overlay (AppKit) | Covers entire screen, most secure visually |
| App type | Menu bar agent (LSUIElement) | No Dock icon, unobtrusive, always available |
| Password storage | Stored hash in config file | `~/.clawlock/config.json` with argon2id |
| Input blocking | Block everything | CGEvent tap suppresses all shortcuts including Cmd+Tab, Cmd+Space, Force Quit |
| Visual style | Minimal dark overlay | Semi-transparent dark + blur + centered password field |
| Safety escape | SSH kill switch | `clawlock --unlock` via Unix domain socket, or process kill |

## Architecture

### Package Structure

```
clawLock/
├── Package.swift
├── Sources/
│   ├── ClawLockCore/              # library target (testable)
│   │   ├── EventTap.swift         # CGEvent tap: intercept all mouse + keyboard
│   │   ├── OverlayWindow.swift    # NSWindow (screenSaver+1, borderless, all screens)
│   │   ├── PasswordStore.swift    # argon2id hash read/write
│   │   ├── LockController.swift   # state machine: idle → locked → unlocking
│   │   └── SocketServer.swift     # Unix domain socket for SSH kill switch
│   └── clawlock/                  # executable target
│       └── main.swift             # CLI args + NSApplication + menu bar setup
└── Tests/
    └── ClawLockCoreTests/
```

### Subsystems

#### 1. Menu Bar Agent
- `NSStatusItem` with a lock icon in the system menu bar
- Dropdown menu: **Lock**, **Change Password**, **Quit**
- App runs as `LSUIElement` (set in Info.plist) — no Dock icon
- When "Lock" is clicked, triggers the LockController

#### 2. Overlay Window
- `NSWindow` with:
  - `level: .screenSaver + 1` (above screen saver, above almost everything)
  - `styleMask: .borderless` (no title bar, no resize)
  - `collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary]`
- Covers all connected displays (one window per screen)
- Background: `NSVisualEffectView` with dark material + additional dark tint layer
- Center: `NSSecureTextField` for password input, styled minimally
- Feedback: "Incorrect password" label with shake animation on wrong attempts

#### 3. Event Tap (CGEvent)
- `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(~0), ...)`
- Callback logic:
  - When locked: suppress ALL events, except route keyboard events to the password field
  - When unlocked: pass through everything (tap disabled)
- Blocks: Cmd+Tab, Cmd+Space, Cmd+Opt+Esc, Mission Control, all function keys, mouse movement outside overlay
- Mouse warped back to center if it attempts to leave
- Requires Accessibility permission — app should prompt on first launch

#### 4. Password Store
- Location: `~/.clawlock/config.json`
- Format:
  ```json
  {
    "password_hash": "<argon2id hash string>",
    "created_at": "2026-03-03T12:00:00Z"
  }
  ```
- Argon2id hashing (via swift-crypto or vendored implementation)
- `set-password` flow: prompt for new password twice, hash, write to config
- On lock: load hash from config, verify each attempt against it
- If no config exists, prompt user to set a password before first lock

#### 5. SSH Kill Switch
- Unix domain socket at `/tmp/clawlock.sock`
- SocketServer listens for unlock commands while locked
- CLI: `clawlock --unlock` connects to socket, sends unlock signal
- Also: plain `kill` / `killall clawlock` works (event tap dies with process, overlay disappears)
- Socket is removed on clean exit

### Lock Flow

```
User clicks "Lock" in menu bar (or runs `clawlock lock`)
  │
  ├→ LockController transitions: idle → locked
  ├→ OverlayWindow.show() — spawn borderless windows on all screens
  ├→ EventTap.enable() — start intercepting all input
  ├→ Mouse warped to center of primary display
  ├→ NSSecureTextField becomes first responder
  │
  └→ User types password + Enter
       │
       ├→ PasswordStore.verify(input) == false
       │    → Shake animation, "Incorrect password", clear field
       │
       └→ PasswordStore.verify(input) == true
            ├→ EventTap.disable()
            ├→ OverlayWindow.hide()
            └→ LockController transitions: locked → idle
```

### Unlock via SSH

```
Remote session: `clawlock --unlock`
  │
  ├→ Connects to /tmp/clawlock.sock
  ├→ Sends unlock command
  │
  └→ SocketServer receives command
       ├→ EventTap.disable()
       ├→ OverlayWindow.hide()
       └→ LockController transitions: locked → idle
```

## Platform Requirements

- macOS 13+ (Ventura)
- Swift 5.9+ / Xcode 15+
- Accessibility permission (System Settings → Privacy & Security → Accessibility)

## Security Considerations

- Password never stored in plaintext — argon2id only
- Event tap runs at session level, not process level — covers all apps
- Overlay at `.screenSaver + 1` is above Notification Center, Spotlight, etc.
- Socket at `/tmp/clawlock.sock` has owner-only permissions (0600)
- No timeout on lock — stays locked until password or kill
