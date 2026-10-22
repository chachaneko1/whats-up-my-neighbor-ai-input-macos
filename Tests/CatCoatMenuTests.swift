import AppKit

final class MenuTarget: NSObject {
    @objc func select(_ sender: NSMenuItem) { }
}

@main enum CatCoatMenuTests {
    static func main() {
        let target = MenuTarget()
        let (root, items) = CatCoatMenu.make(target: target, action: #selector(MenuTarget.select(_:)))
        precondition(root.title == "選擇貓咪花色")
        precondition(root.submenu?.items.count == 9)
        precondition(items.count == CatAppearance.presetIDs.count)
        for (id, title) in zip(CatAppearance.presetIDs, CatAppearance.presetNames) {
            let item = items[id]!
            precondition(item.title == title)
            precondition(item.representedObject as? String == id)
            precondition(item.target === target)
        }
        print("CatCoatMenuTests passed (9 selectable coats)")
    }
}
