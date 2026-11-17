public struct DrawerPresentation {
    public private(set) var isShown = false
    private var revision: UInt64 = 0

    public init() {}

    public mutating func show() {
        isShown = true
        revision &+= 1
    }

    public mutating func hide() {
        isShown = false
        revision &+= 1
    }

    public var recoveryToken: UInt64? { isShown ? revision : nil }

    public func canRecover(_ token: UInt64) -> Bool { isShown && revision == token }
}
