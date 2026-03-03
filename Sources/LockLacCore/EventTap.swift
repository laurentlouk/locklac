import ApplicationServices
import CoreGraphics
import Foundation

public final class EventTap {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var enabled = false

    /// Callback invoked with keyboard events (keyDown) while locked.
    /// Return true to allow the event through, false to suppress.
    public var onKeyEvent: ((_ keyCode: UInt16, _ flags: CGEventFlags) -> Bool)?

    public init() {}

    public func start() -> Bool {
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        )
        guard trusted else { return false }

        let eventMask: CGEventMask = ~0

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
                return tap.handleEvent(type: type, event: event)
            },
            userInfo: refcon
        )

        guard let eventTap else { return false }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        enabled = true
        return true
    }

    public func stop() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        self.eventTap = nil
        self.runLoopSource = nil
        enabled = false
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        if type == .keyDown, let onKeyEvent {
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            if onKeyEvent(keyCode, flags) {
                return Unmanaged.passRetained(event)
            }
        }

        // Suppress everything else
        return nil
    }
}
