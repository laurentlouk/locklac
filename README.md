# LockLac

A macOS menu bar app that locks your screen with a fullscreen dark overlay while background processes keep running. Traps all keyboard and mouse input — only unlocks with the correct password or Touch ID.

## Install

### Homebrew Cask (recommended)

```sh
brew tap laurentlouk/locklac
brew install --cask locklac
```

This installs lockLac.app to `/Applications` and symlinks the `locklac` CLI to your PATH.

### Build from source

Requires macOS 13+ (Ventura), Swift 5.9+ / Xcode 15+.

```sh
git clone https://github.com/laurentlouk/locklac.git
cd locklac
swift build -c release
# Binary is at .build/release/locklac
# Or build the .app bundle:
bash scripts/package-app.sh
cp -R lockLac.app /Applications/
xattr -d com.apple.quarantine /Applications/lockLac.app
```

> **Note:** The `xattr` command removes the macOS Gatekeeper quarantine flag. This is needed because the app is not signed with an Apple Developer ID. The Homebrew Cask install handles this automatically.

## Requirements

- macOS 13+ (Ventura)
- Accessibility permission (System Settings → Privacy & Security → Accessibility)

## Authorization

On first launch, macOS may block the app because it is not signed with an Apple Developer ID. To authorize it:

1. **Remove the Gatekeeper quarantine flag:**

   ```sh
   xattr -d com.apple.quarantine /Applications/lockLac.app
   ```

2. **Grant Accessibility permission:**

   Go to **System Settings → Privacy & Security → Accessibility** and enable **lockLac**.

   This is required for the app to intercept keyboard and mouse input while locked.

> **Tip:** If you installed via Homebrew Cask, step 1 is handled automatically.

## Run

```sh
# Start the menu bar app (prompts for password on first launch)
locklac

# Start and lock immediately
locklac lock
```

A lock shield icon appears in the menu bar. Click it to **Lock**, **Change Password**, or **Quit**.

## Unlock

- **Password:** Type your password into the overlay and press Enter
- **Touch ID:** Prompted automatically on Macs with Touch ID
- **SSH kill switch:** `locklac --unlock` from another terminal
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
