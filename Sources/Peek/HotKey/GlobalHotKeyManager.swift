import AppKit
import Carbon.HIToolbox

/// 全局快捷键管理器，基于 Carbon EventHotKey。
/// 相比 NSEvent 全局监听的优势：无需辅助功能授权，系统级可靠，不受前台应用影响。
final class GlobalHotKeyManager {

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var currentSignature: UInt32 = 0
    private var currentID: UInt32 = 0
    private var currentHotKey: HotKey?
    private var onTrigger: (() -> Void)?

    /// 固定签名，防止与其它应用冲突
    private static let signature: OSType = 0x4C554D45   // "LUME"

    var registeredHotKey: HotKey? { currentHotKey }

    /// 注册（或重新注册）全局快捷键
    @discardableResult
    func register(_ hotKey: HotKey, onTrigger: @escaping () -> Void) -> Bool {
        unregister()

        guard hotKey.isValid else { return false }

        self.onTrigger = onTrigger

        // 保证 ID 唯一且递增，避免重复注册同一 ID 时系统认为是同一个
        currentID &+= 1
        if currentID == 0 { currentID = 1 }

        var hotKeyID = EventHotKeyID(signature: Self.signature, id: currentID)
        currentSignature = Self.signature

        let ref = UnsafeMutablePointer<EventHotKeyRef?>.allocate(capacity: 1)
        defer { ref.deallocate() }

        let status = RegisterEventHotKey(
            UInt32(hotKey.keyCode),
            hotKey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            ref
        )

        guard status == noErr, let created = ref.pointee else {
            return false
        }

        hotKeyRef = created
        currentHotKey = hotKey

        // 安装事件处理器
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.hotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        return handlerStatus == noErr
    }

    func unregister() {
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        currentHotKey = nil
    }

    deinit {
        unregister()
    }

    // MARK: - C 回调

    /// Carbon 回调必须是 C 函数指针，无法捕获上下文，
    /// 因此用 Unmanaged 从 userData 取回实例。
    private static let hotKeyEventHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else { return status }

        let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()

        if hotKeyID.signature == manager.currentSignature && hotKeyID.id == manager.currentID {
            DispatchQueue.main.async {
                manager.onTrigger?()
            }
        }
        return noErr
    }
}