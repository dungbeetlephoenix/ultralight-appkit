import AppKit

// One Objective-C construction path for the layout relationships shared by views.
@inline(never)
func uiConstraint(_ view: NSView, _ attribute: NSLayoutConstraint.Attribute,
                  _ other: NSView?, _ otherAttribute: NSLayoutConstraint.Attribute,
                  _ relation: NSLayoutConstraint.Relation, _ constant: CGFloat) -> NSLayoutConstraint {
    NSLayoutConstraint(item: view, attribute: attribute, relatedBy: relation,
                       toItem: other, attribute: otherAttribute, multiplier: 1, constant: constant)
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
