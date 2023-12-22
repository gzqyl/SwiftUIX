//
// Copyright (c) Vatsal Manot
//

#if os(macOS)

import AppKit
import Swift
import SwiftUI

extension _CocoaList: NSViewRepresentable {
    public typealias NSViewType = _PlatformTableViewContainer<Configuration>
    
    func makeNSView(
        context: Context
    ) -> NSViewType {
        NSViewType(coordinator: context.coordinator)
    }
    
    func updateNSView(
        _ view: NSViewType,
        context: Context
    ) {
        func updateCocoaScrollProxy() {
            if !(context.environment._cocoaScrollViewProxy?.base.wrappedValue === view) {
                context.environment._cocoaScrollViewProxy?.base.wrappedValue = view
            }
        }
        
        updateCocoaScrollProxy()
        
        context.coordinator.representableWillUpdate()
        
        context.coordinator.configuration = configuration
        context.coordinator.preferences = _cocoaListPreferences

        context.coordinator.representableDidUpdate()
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(
            configuration: configuration,
            preferences: _cocoaListPreferences
        )
    }
}

extension _CocoaList {
    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        enum DirtyFlag {
            case isFirstRun
            case dataChanged
            case didJustReload
        }
        
        var dirtyFlags: Set<DirtyFlag> = []
        var cache = _CocoaListCache<Configuration>()
        var preferredScrollViewConfiguration: CocoaScrollViewConfiguration<AnyView> = nil
        
        private var scrollViewConfiguration: CocoaScrollViewConfiguration<AnyView> {
            var result = preferredScrollViewConfiguration
            
            if dirtyFlags.contains(.isFirstRun) {
                result.showsVerticalScrollIndicator = false
                result.showsHorizontalScrollIndicator = false
            }
            
            return result
        }
        
        public var configuration: Configuration {
            didSet {
                let reload = cache.update(configuration: configuration)
                
                if reload {
                    dirtyFlags.insert(.dataChanged)
                }
            }
        }
        
        public var preferences: _CocoaListPreferences
        
        weak var tableViewContainer: _PlatformTableViewContainer<Configuration>?
        
        var tableView: NSTableView? {
            tableViewContainer?.tableView
        }
        
        public init(configuration: Configuration, preferences: _CocoaListPreferences) {
            self.configuration = configuration
            self.preferences = preferences
            
            self.dirtyFlags.insert(.isFirstRun)
        }
        
        func representableWillUpdate() {
            
        }
        
        func representableDidUpdate() {
            guard let view = tableViewContainer else {
                return
            }
            
            defer {
                DispatchQueue.main.async {
                    self.dirtyFlags.remove(.isFirstRun)
                }
            }
            
            view.configure(with: scrollViewConfiguration)
            
            if self.dirtyFlags.contains(.dataChanged) {
                reload()
            } else {
                if !dirtyFlags.contains(.didJustReload) {
                    updateTableViewCells()
                }
            }
        }
        
        private func reload() {
            guard let tableViewContainer else {
                return
            }
            
            _withoutAppKitOrUIKitAnimation(self.dirtyFlags.contains(.isFirstRun)) {
                dirtyFlags.remove(.dataChanged)
                
                guard !dirtyFlags.contains(.didJustReload) else {
                    DispatchQueue.main.async {
                        tableViewContainer.reloadData()
                    }
                    
                    return
                }
                
                tableViewContainer.reloadData()
                
                dirtyFlags.insert(.didJustReload)
                
                DispatchQueue.main.async {
                    self.dirtyFlags.remove(.didJustReload)
                }
            }
        }
        
        func tableView(
            _ tableView: NSTableView,
            heightOfRow row: Int
        ) -> CGFloat {
            switch preferences.cell.sizingOptions {
                case .auto:
                    return NSTableCellView.automaticSize.height
                case .fixed(let width, let height):
                    assert(width == nil, "Fixed width is currently unsupported.")
                    
                    guard let height else {
                        return NSTableCellView.automaticSize.height
                    }
                    
                    return height
                case .custom(let height):
                    switch height {
                        case .indexPath(let height):
                            let size = height(IndexPath(item: row, section: 0))
                            
                            assert(size.width == nil, "Fixed width is currently unsupported.")
                            
                            guard let height = size.height else {
                                return NSTableCellView.automaticSize.height
                            }
                            
                            return height
                    }
            }
        }
        
        func numberOfRows(in tableView: NSTableView) -> Int {
            configuration.data.itemsCount
        }
        
        func tableView(
            _ tableView: NSTableView,
            objectValueFor tableColumn: NSTableColumn?,
            row: Int
        ) -> Any? {
            configuration.data.payload.first?[row]
        }
        
        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard let tableViewContainer, let tableView = self.tableView else {
                assertionFailure()
                
                return nil
            }
            
            let identifier = NSUserInterfaceItemIdentifier("_PlatformTableCellView")
            let item = configuration.data.payload.first![row]
            let itemID = item[keyPath: configuration.data.itemID]
            let sectionID = configuration.data.payload.first!.model[keyPath: configuration.data.sectionID]
            let itemPath = _CocoaListCache<Configuration>.ItemPath(item: itemID, section: sectionID)
            
            let view = (tableView.makeView(withIdentifier: identifier, owner: self) as? _PlatformTableCellView<Configuration>) ?? _PlatformTableCellView<Configuration>(
                parent: tableViewContainer,
                identifier: identifier
            )
            
            view.indexPath = IndexPath(item: row, section: 0)
            
            view.prepareForUse(
                payload: .init(
                    itemPath: itemPath,
                    item: item,
                    content: configuration.viewProvider.rowContent(item)
                ),
                tableView: tableView
            )
            
            return view
        }
        
        func updateTableViewCells() {
            guard let tableView else {
                return
            }
            
            for cell in tableView._visibleTableViewCellViews() {
                guard let cell = cell as? _PlatformTableCellView<Configuration>, !cell.stateFlags.contains(.wasJustPutIntoUse) else {
                    continue
                }
                
                guard let item = cell.payload?.item else {
                    continue
                }
                
                assert(cell.payload != nil)
                
                cell.payload?.content = configuration.viewProvider.rowContent(item)
            }
        }
        
        func tableView(
            _ tableView: NSTableView,
            didAdd rowView: NSTableRowView,
            forRow row: Int
        ) {
            if rowView.translatesAutoresizingMaskIntoConstraints {
                rowView.translatesAutoresizingMaskIntoConstraints = false
            }
        }
    }
}

extension _CocoaList.Coordinator {
    func _fastHeight(
        for indexPath: IndexPath
    ) -> CGFloat? {
        switch preferences.cell.sizingOptions {
            case .auto:
                return nil
            case .fixed(let width, let height):
                assert(width == nil, "Fixed width is currently unsupported.")
                
                guard let height else {
                    return nil
                }
                
                return height
            case .custom(let height):
                switch height {
                    case .indexPath(let height):
                        let size = height(indexPath)
                        
                        assert(size.width == nil, "Fixed width is currently unsupported.")
                        
                        guard let height = size.height else {
                            return nil
                        }
                        
                        return height
                }
        }
    }
}

// MARK: - Helpers

extension NSTableView {
    func _visibleTableViewCellViews() -> [NSTableCellView] {
        var cellViews: [NSTableCellView] = []
        
        for row in 0..<self.numberOfRows {
            for column in 0..<self.numberOfColumns {
                if let cellView = view(atColumn: column, row: row, makeIfNecessary: false) as? NSTableCellView {
                    cellViews.append(cellView)
                }
            }
        }
        
        return cellViews
    }
}

#endif