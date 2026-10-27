import AppKit

enum CatCoatMenu {
    static func make(target: AnyObject, action: Selector) -> (NSMenuItem, [String: NSMenuItem]) {
        let root = NSMenuItem(title: "選擇貓咪花色", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        var items: [String: NSMenuItem] = [:]
        for (id, name) in zip(CatAppearance.presetIDs, CatAppearance.presetNames) {
            let item = NSMenuItem(title: name, action: action, keyEquivalent: "")
            item.target = target
            item.representedObject = id
            submenu.addItem(item)
            items[id] = item
        }
        root.submenu = submenu
        return (root, items)
    }
}
