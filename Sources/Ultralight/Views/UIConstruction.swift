import AppKit
import Combine

// One Objective-C construction path for the layout relationships shared by views.
@inline(never)
func uiConstrain(_ view: NSView, _ attribute: NSLayoutConstraint.Attribute,
                  _ other: NSView?, _ otherAttribute: NSLayoutConstraint.Attribute,
                  _ relation: NSLayoutConstraint.Relation, _ constant: CGFloat) {
    NSLayoutConstraint(item: view, attribute: attribute, relatedBy: relation,
                       toItem: other, attribute: otherAttribute, multiplier: 1, constant: constant).isActive = true
}

// Common rectangular layouts share the same explicit edge constraints.
@inline(never) func uiAlign(_ view: NSView, _ edge: NSLayoutConstraint.Attribute,
                           to parent: NSView, offset: CGFloat = 0) {
    uiConstrain(view, edge, parent, edge, .equal, offset)
}

@inline(never) func uiDimension(_ view: NSView, _ dimension: NSLayoutConstraint.Attribute, _ value: CGFloat) {
    uiConstrain(view, dimension, nil, .notAnAttribute, .equal, value)
}

@inline(never) func uiFill(_ view: NSView, in parent: NSView, top: CGFloat = 0) {
    uiConstrain(view, .top, parent, .top, .equal, top)
    uiConstrain(view, .leading, parent, .leading, .equal, 0)
    uiConstrain(view, .trailing, parent, .trailing, .equal, 0)
    uiConstrain(view, .bottom, parent, .bottom, .equal, 0)
}

@inline(never) func uiSize(_ view: NSView, width: CGFloat, height: CGFloat) {
    uiConstrain(view, .width, nil, .notAnAttribute, .equal, width)
    uiConstrain(view, .height, nil, .notAnAttribute, .equal, height)
}

@inline(never) func uiLabel(_ text: String) -> NSTextField {
    NSTextField(labelWithString: text)
}

@inline(never) func uiButton(_ text: String) -> NSButton {
    NSButton(title: text, target: nil, action: nil)
}

@inline(never) func uiStyleLabel(_ label: NSTextField, _ size: CGFloat, _ weight: NSFont.Weight, _ color: UInt) {
    label.font = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    label.textColor = NSColor(hex: color)
}

@inline(never) func uiStyleButton(_ button: NSButton, _ size: CGFloat, _ weight: NSFont.Weight,
                                _ monospace: Bool, _ color: UInt) {
    button.bezelStyle = .inline
    button.isBordered = false
    button.font = monospace ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size)
    button.contentTintColor = NSColor(hex: color)
}

@inline(never) func uiInstall(_ parent: NSView, _ views: [NSView]) {
    for view in views {
        view.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(view)
    }
}

@inline(never) func uiBackground(_ view: NSView, _ color: UInt, alpha: CGFloat = 1) {
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor(hex: color, alpha: alpha).cgColor
}

@inline(never) func uiBorder(_ view: NSView, _ color: UInt) {
    view.wantsLayer = true
    view.layer?.borderColor = NSColor(hex: color).cgColor
    view.layer?.borderWidth = 1
}

@inline(never) func uiStack(_ views: [NSView], _ orientation: NSUserInterfaceLayoutOrientation, _ spacing: CGFloat) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = orientation
    stack.spacing = spacing
    return stack
}


// Layout-only panels need no custom class: the view tree owns the separator,
// and the associated cancellables keep their ordered subscriptions alive.
@inline(never) func uiContainer(border: NSRectEdge, frame: NSRect = .zero) -> NSView {
    let view = NSView(frame: frame)
    view.wantsLayer = true
    let line: NSView
    switch border {
    case .minY:
        line = NSView(frame: NSRect(x: 0, y: 0, width: frame.width, height: 1))
        line.autoresizingMask = [.width, .maxYMargin]
    case .maxY:
        line = NSView(frame: NSRect(x: 0, y: frame.height - 1, width: frame.width, height: 1))
        line.autoresizingMask = [.width, .minYMargin]
    default:
        line = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: frame.height))
        line.autoresizingMask = [.height, .maxXMargin]
    }
    uiBackground(line, 0x1a1a1a)
    view.addSubview(line)
    return view
}

private var uiSubscriptionsKey: UInt8 = 0
private var uiActionKey: UInt8 = 0

@inline(never) func uiRetain(_ subscriptions: [AnyCancellable], on view: NSView) {
    objc_setAssociatedObject(view, &uiSubscriptionsKey, subscriptions, .OBJC_ASSOCIATION_RETAIN)
}

@inline(never) func uiAction(_ button: NSButton, _ action: @escaping () -> Void) {
    let wrapper = UIAction(action)
    objc_setAssociatedObject(button, &uiActionKey, wrapper, .OBJC_ASSOCIATION_RETAIN)
    button.target = wrapper
    button.action = #selector(UIAction.invoke)
}

private final class UIAction: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func invoke() { action() }
}
