import Carbon
import Foundation

@MainActor
final class GlobalHotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        install()
    }

    private func install() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let pointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in manager.action() }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &eventHandlerRef
        )

        let hotKeyID = EventHotKeyID(signature: fourCharacterCode("NDGE"), id: 1)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func fourCharacterCode(_ string: String) -> FourCharCode {
        string.utf8.reduce(0) { ($0 << 8) + FourCharCode($1) }
    }
}
