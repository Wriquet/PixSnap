import Testing
import Cocoa
import Carbon
@testable import PixSnap

@MainActor
struct PreferencesInteractionTests {
    private func keyEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, chars: String = "") throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: chars,
            charactersIgnoringModifiers: chars,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    @Test func shortcutRecorderCapturesCommandCombosViaPerformKeyEquivalent() throws {
        let btn = ShortcutRecordButton(action: .restorePin)
        var recorded: (HotKeyAction, UInt32, UInt32, String)?
        btn.onShortcutRecorded = { act, kc, mods, disp in
            recorded = (act, kc, mods, disp)
        }

        btn.startRecording()
        #expect(btn.isRecording == true)

        // Simulate ⌘ + ⇧ + Z arriving via performKeyEquivalent (which AppKit uses for ⌘ shortcuts)
        let cmdShiftZ = try keyEvent(keyCode: 6, modifiers: [.command, .shift], chars: "z")
        let handled = btn.performKeyEquivalent(with: cmdShiftZ)
        #expect(handled == true)
        #expect(btn.isRecording == false)
        #expect(recorded?.0 == .restorePin)
        #expect(recorded?.1 == 6)
        #expect(recorded?.2 == UInt32(cmdKey | shiftKey))
        #expect(recorded?.3 == "⇧ + ⌘ + Z")
    }

    @Test func shortcutRecorderFormatsKeyCodeWithoutCharactersAndHandlesEscAndInvalid() throws {
        let btn = ShortcutRecordButton(action: .ocrCapture)
        var invalidMsg: String?
        var recordedDisplay: String?
        btn.onInvalidShortcut = { invalidMsg = $0 }
        btn.onShortcutRecorded = { _, _, _, disp in recordedDisplay = disp }

        btn.startRecording()

        // Bare 'A' must be rejected and stay recording
        btn.handleRecordedKeyEvent(try keyEvent(keyCode: 0, modifiers: [], chars: "a"))
        #expect(invalidMsg != nil)
        #expect(btn.isRecording == true)

        // Option + '/' with empty characters (e.g. Chinese IME) must still format cleanly as "⌥ + /"
        btn.handleRecordedKeyEvent(try keyEvent(keyCode: 44, modifiers: [.option], chars: ""))
        #expect(btn.isRecording == false)
        #expect(recordedDisplay == "⌥ + /")

        // Esc cancels recording cleanly
        btn.startRecording()
        #expect(btn.isRecording == true)
        btn.handleRecordedKeyEvent(try keyEvent(keyCode: 53, modifiers: [], chars: "\u{1b}"))
        #expect(btn.isRecording == false)
    }

    @Test func glassTabBarTracksSelectedIndexAndDisabledWindowMove() {
        let bar = GlassTabBar(items: [
            ("通用与保存", "gearshape"),
            ("全局快捷键", "command"),
            ("截图与贴图", "camera.viewfinder")
        ])
        #expect(bar.mouseDownCanMoveWindow == false)
        #expect(bar.selectedIndex == 0)

        bar.setSelected(index: 2, animated: false)
        #expect(bar.selectedIndex == 2)

        bar.setSelected(index: 1, animated: false)
        #expect(bar.selectedIndex == 1)
    }
}
