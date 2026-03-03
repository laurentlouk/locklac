# lockLac

A macOS menu bar app that locks your screen with a fullscreen dark overlay while background processes keep running. Traps all keyboard and mouse input — only unlocks with the correct password or Touch ID.

## Requirements

- macOS 13+ (Ventura)
- Swift 5.9+ / Xcode 15+
- Accessibility permission (System Settings → Privacy & Security → Accessibility)

## Build

```sh
swift build                # debug build
swift build -c release     # optimized release build
```

## Run

```sh
# Set your lock password (required before first lock)
swift run locklac set-password

# Start the menu bar app
swift run locklac

# Start and lock immediately
swift run locklac lock
```

A lock shield icon appears in the menu bar. Click it to **Lock**, **Change Password**, or **Quit**.

## Unlock

- **Password:** Type your password into the overlay and press Enter
- **Touch ID:** Prompted automatically on Macs with Touch ID
- **SSH kill switch:** `swift run locklac --unlock` from another terminal
- **Force kill:** `killall locklac`

## Test

```sh
swift test                       # run all tests
swift test --filter <TestName>   # run a single test
```

## CLI Reference

| Command | Description |
|---------|-------------|
| `locklac` | Start the menu bar app |
| `locklac lock` | Start and lock immediately |
| `locklac set-password` | Set or change the lock password |
| `locklac --unlock` | Unlock a running instance (SSH) |
| `locklac --version` | Print version |
| `locklac --help` | Print help |

## Regenerate App Icon

```sh
swift scripts/generate-icon.swift
iconutil -c icns AppIcon.iconset -o Sources/locklac/Resources/AppIcon.icns
rm -rf AppIcon.iconset
```
