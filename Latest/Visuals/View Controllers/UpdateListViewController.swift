//
//  ViewController.swift
//  Latest
//
//  Created by Max Langer on 15.02.17.
//  Copyright © 2017 Max Langer. All rights reserved.
//

import Cocoa

protocol UpdateListViewControllerDelegate : class {    
    func shouldExpandDetail()
    func shouldCollapseDetail()
}

class UpdateListViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, AppBundleDelegate {

    var apps = [AppBundle]()
    private var _appsToDelete : [AppBundle]?
    
    weak var delegate : UpdateListViewControllerDelegate?
    
    weak var detailViewController : UpdateDetailsViewController?
    
    @IBOutlet weak var noUpdatesAvailableLabel: NSTextField!
    @IBOutlet weak var updatesLabel: NSTextField!
    @IBOutlet weak var rightMarginConstraint: NSLayoutConstraint!
    
    @IBOutlet weak var toolbarDivider: NSBox!
    
    @IBOutlet weak var tableViewMenu: NSMenu!
    
    var updateChecker = UpdateChecker()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Do any additional setup after loading the view.
        
        if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "MLMUpdateCellIdentifier"), owner: self) {
            self.tableView.rowHeight = cell.frame.height
        }
        
        self.updateChecker.appUpdateDelegate = self
        
        self.scrollViewDidScroll(nil)
        
        self.tableViewMenu.delegate = self
        self.tableView.menu = self.tableViewMenu
        
        self.updatesLabel.stringValue = NSLocalizedString("Up to Date!", comment: "")
        
        self._updateEmtpyStateVisibility()
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        
        guard let scrollView = self.tableView.enclosingScrollView else { return }
        
        let topConstraint = NSLayoutConstraint(item: scrollView, attribute: .top, relatedBy: .equal, toItem: self.view.window?.contentLayoutGuide, attribute: .top, multiplier: 1.0, constant: 3)
        topConstraint.isActive = true
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.scrollViewDidScroll(_:)), name: NSScrollView.didLiveScrollNotification, object: self.tableView.enclosingScrollView)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        
        self.apps.forEach { (app) in
            NSFileCoordinator.removeFilePresenter(app)
        }
    }
    
    // MARK: - TableView Stuff
    
    @IBOutlet weak var tableView: NSTableView!
    
    @objc func scrollViewDidScroll(_ notification: Notification?) {
        guard let scrollView = self.tableView.enclosingScrollView else {
            return
        }
        
        let pos = scrollView.contentView.bounds.origin.y
        self.toolbarDivider.alphaValue = min(pos / 15, 1)
    }
    
    // MARK: Table View Delegate
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        
        let app = self.apps[row]
        
        guard let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "MLMUpdateCellIdentifier"), owner: self) as? UpdateCell,
            let info = app.newestVersion,
            let url = app.appURL else {
            return nil
        }
        
        var version = ""
        var newVersion = ""
        
        if let v = app.version.versionNumber, let nv = info.version.versionNumber {
            version = v
            newVersion = nv
            
            // If the shortVersion string is identical, but the bundle version is different
            // Show the Bundle version in brackets like: "1.3 (21)"
            if version == newVersion, let v = app.version?.buildNumber, let nv = info.version.buildNumber {
                version += " (\(v))"
                newVersion += " (\(nv))"
            }
        } else if let v = app.version.buildNumber, let nv = info.version.buildNumber {
            version = v
            newVersion = nv
        }
        
        cell.textField?.stringValue = app.appName
        cell.currentVersionTextField?.stringValue = String(format:  NSLocalizedString("Your version: %@", comment: "Current Version String"), "\(version)")
        cell.newVersionTextField?.stringValue = String(format: NSLocalizedString("New version: %@", comment: "New Version String"), "\(newVersion)")
        
        DispatchQueue.main.async {
            cell.imageView?.image = NSWorkspace.shared.icon(forFile: url.path)
        }
        
        return cell
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "MLMUpdateCellIdentifier"), owner: self) else {
            return 50
        }
        
        return cell.frame.height
    }
    
    func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
        if edge == .trailing {
            let action = NSTableViewRowAction(style: .regular, title: NSLocalizedString("Update", comment: "Update String"), handler: { (action, row) in
                self._openApp(atIndex: row)
            })
            
            action.backgroundColor = #colorLiteral(red: 0.2588235438, green: 0.7568627596, blue: 0.9686274529, alpha: 1)
            
            return [action]
        } else if edge == .leading {
            let action = NSTableViewRowAction(style: .regular, title: NSLocalizedString("Show in Finder", comment: "Revea in Finder Row action"), handler: { (action, row) in
                self._showAppInFinder(at: row)
            })
            
            action.backgroundColor = #colorLiteral(red: 0.6975218654, green: 0.6975218654, blue: 0.6975218654, alpha: 1)
            
            return [action]
        }
        
        return []
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        let index = self.tableView.selectedRow
        
        if index == -1 {
            return
        }
        
        let app = self.apps[index]
        
        guard let detailViewController = self.detailViewController else {
            return
        }
        
        if let url = app.newestVersion?.releaseNotes as? URL {
            self.delegate?.shouldExpandDetail()
            detailViewController.display(url: url)
        } else if let string = app.newestVersion?.releaseNotes as? String {
            self.delegate?.shouldExpandDetail()
            detailViewController.display(html: string)
        }
    }
    
    // MARK: Table View Data Source
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return self.apps.count
    }
    
    // MARK: - Update Checker Delegate
    
    func appDidUpdateVersionInformation(_ app: AppBundle) {
        self.updateChecker.progressDelegate?.didCheckApp()
        
        if let index = self._appsToDelete?.index(where: { $0 == app }) {
            self._appsToDelete?.remove(at: index)
        }
        
        if let versionBundle = app.newestVersion, versionBundle.version > app.version {
            self._add(app)
        } else if let index = self.apps.index(where: { $0 == app }) {
            self.apps.remove(at: index)
            self.tableView.removeRows(at: IndexSet(integer: index), withAnimation: .slideUp)
            
            NSFileCoordinator.removeFilePresenter(app)
        }
        
        self._updateTitleAndBatch()
        self._updateEmtpyStateVisibility()
    }
    
    func finishedCheckingForUpdates() {
        guard let apps = self._appsToDelete, apps.count != 0 else { return }
        
        apps.forEach { (app) in
            guard let index = self.apps.index(where: { $0 == app }) else { return }
            
            self.tableView.removeRows(at: IndexSet(integer: index), withAnimation: .slideUp)
            self.apps.remove(at: index)
            NSFileCoordinator.removeFilePresenter(app)
        }
        
        self._updateTitleAndBatch()
        self._updateEmtpyStateVisibility()
    }

    
    // MARK: - Public Methods
    
    func checkForUpdates() {
        self._appsToDelete = self.apps
        self.updateChecker.run()
    }

    
    // MARK: - Menu Item Stuff
    
    @IBAction func openApp(_ sender: NSMenuItem?) {
        self._openApp(atIndex: sender?.representedObject as? Int ?? self.tableView.selectedRow)
    }
    
    @IBAction func showAppInFinder(_ sender: NSMenuItem?) {
        self._showAppInFinder(at: sender?.representedObject as? Int ?? self.tableView.selectedRow)
    }
    
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else {
            return super.validateMenuItem(menuItem)
        }
        
        switch action {
        case #selector(openApp(_:)),
             #selector(showAppInFinder(_:)):
            return menuItem.representedObject as? Int ?? self.tableView.selectedRow != -1
        default:
            return super.validateMenuItem(menuItem)
        }
    }
    
    // MARK: Delegate
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        let row = self.tableView.clickedRow
        
        guard row != -1 else { return }
        for item in menu.items {
            item.representedObject = row
        }
    }
    
    // MARK: - Private Methods

    private func _add(_ app: AppBundle) {
        guard !self.apps.contains(where: { $0 == app }) else {
            guard let index = self.apps.index(of: app) else { return }
            
            self.tableView.reloadData(forRowIndexes: IndexSet(integer: index), columnIndexes: IndexSet(integer: 0))
            
            return
        }
        
        self.apps.append(app)
        
        self.apps.sort { (first, second) -> Bool in
            return first.appName < second.appName
        }
        
        guard let index = self.apps.index(of: app) else {
            return
        }
        
        NSFileCoordinator.addFilePresenter(app)
        
        self.tableView.insertRows(at: IndexSet(integer: index), withAnimation: .slideDown)
    }
    
    private func _openApp(atIndex index: Int) {
        DispatchQueue.main.async {
            if index < 0 || index >= self.apps.count {
                return
            }
            
            let app = self.apps[index]
            var appStoreURL : URL?
            
            if let appStoreApp = app as? MacAppStoreAppBundle {
                appStoreURL = appStoreApp.appStoreURL
            }
            
            guard let url = appStoreURL ?? app.appURL else {
                return
            }
            
            NSWorkspace.shared.open(url)
        }
    }

    private func _showAppInFinder(at index: Int) {
        if index < 0 || index >= self.apps.count {
            return
        }
        
        let app = self.apps[index]
        
        guard let url = app.appURL else { return }
        
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    private func _updateEmtpyStateVisibility() {
        if self.apps.count == 0 && !self.tableView.isHidden {
            self.tableView.alphaValue = 0
            self.tableView.isHidden = true
            self.toolbarDivider.isHidden = true
            self.noUpdatesAvailableLabel.isHidden = false
        } else if self.apps.count != 0 && tableView.isHidden {
            self.tableView.alphaValue = 1
            self.tableView.isHidden = false
            self.toolbarDivider.isHidden = false
            self.noUpdatesAvailableLabel.isHidden = true
        }
    }
    
    private func _updateTitleAndBatch() {
        let count = self.apps.count
        
        if count == 0 {
            NSApplication.shared.dockTile.badgeLabel = ""
            self.updatesLabel.stringValue = NSLocalizedString("Up to Date!", comment: "")
        } else {
            NSApplication.shared.dockTile.badgeLabel = NumberFormatter().string(from: count as NSNumber)
            
            let format = NSLocalizedString("number_of_updates_available", comment: "number of updates available")
            self.updatesLabel.stringValue = String.localizedStringWithFormat(format, count)
        }
    }
    
}

