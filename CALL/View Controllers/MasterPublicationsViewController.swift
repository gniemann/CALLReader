/*
  MasterPublicationsViewController.swift
  CALL

  Created by Gregory Niemann on 1/15/17.
  Copyright © 2017 Greg Niemann. All rights reserved.

  MasterPublicationsViewController - This class implements the main view controller of the app
     The Master implements All/Local filtering, searching, sorting, and allows for the settings
     menu to be accessed
 
     The Master implements the PublicationsViewControllerBase and uses the underlying Realm model
     as the datasource. This allows it to efficiently sort and filter the publications
 
 */

import UIKit
import RealmSwift

class MasterPublicationsViewController: UITableViewController, UISearchResultsUpdating, SortFilterDelegate, DownloadStatusViewDelegate {
    // MARK: Types
    // A pubs manager reference is needed for download events
    let pubsManager = PublicationManager.shared
    
    // these two properties determine which cell the table view uses,
    // based on what type of device it is on (ipad or iphone)
    let cellClass = PublicationTableViewCell.self
    let cellIdentifier = "PublicationTableViewCell"
    
    
    // Network connectivity
    let reachability = Reachability()
    var isConnectedToNetwork = true
    
    // This type sets the possible states of the table - showing all publications or only ones already downloaded
    enum VisiblePublicationsState {
        case all
        case local
    }
    
    // MARK: Properties
    let publicationTypes = PublicationManager.shared.publicationTypes
    let allPublications = PublicationManager.shared.publications
    
    // this breaks the publications down by section
    // so that there is a mapping between publicationTypes and the pubs which go in that section
    var publicationsByType: [Results<Publication>] {
        return sortFilterOptions.typeSortOrder.map {
            allPublications.filter("type == %@", $0).sorted(byKeyPath: "datePublished",
                                                            ascending: !sortFilterOptions.sortDescendingDates)
        }
    }
    
    // At start, all publications are visible. 
    // When visiblePublicationsStatus is changed, this array is filtered as necessary
    lazy var visiblePublications: [Results<Publication>] = self.publicationsByType
    
    var visiblePublicationsStatus: VisiblePublicationsState = .all {
        // resort and filter whenever the status changes (ensures we look at the right ones)
        didSet {
            applySortAndFilters()
        }
    }
    
    // options for sorting and filtering
    var sortFilterOptions = SortFilterOptions()
    
    // the search results controller
    let searchController = UISearchController(searchResultsController: nil)
    var prevSearchText: String = ""
   
    // MARK: UIViewController overrides
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupReachability()
        
        // this sets up automatic row heights for the table cells
        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.estimatedRowHeight = 200
        
        tableView.register(UINib(nibName: cellIdentifier, bundle: nil), forCellReuseIdentifier: cellIdentifier)
        
        // setup the Settings button on the left
        let settingsFont = UIFont(name: "Helvetica", size: 24)
        let settingsButton = UIBarButtonItem(title: "\u{2699}\u{0000FE0E}", style: .plain, target: self,
                                             action: #selector(settingsPressed(_:)))
        settingsButton.setTitleTextAttributes([NSFontAttributeName: settingsFont!], for: .normal)
        navigationItem.leftBarButtonItem = settingsButton
        
        // setup the SortFilter button on the right
        let sortFilterButton = UIBarButtonItem(title: "Sort", style: .plain, target: self,
                                               action: #selector(sortFilterPressed(_:)))
        let sortFilterFont = UIFont.systemFont(ofSize: 14)
        sortFilterButton.setTitleTextAttributes([NSFontAttributeName: sortFilterFont], for: .normal)
        navigationItem.rightBarButtonItem = sortFilterButton
        
        
        // set up the All/Local segmented controller as the titleView
        let allOrLocal = UISegmentedControl(items: ["All Publications", "On This Device"])
        let allOrLocalFont = UIFont.systemFont(ofSize: 14)
        allOrLocal.setTitleTextAttributes([NSFontAttributeName: allOrLocalFont], for: .normal)
        allOrLocal.selectedSegmentIndex = 0
        allOrLocal.addTarget(self, action: #selector(filterSelect(_:)), for: .valueChanged)
        navigationItem.titleView = allOrLocal
        
        navigationItem.title = "CALL Publications"
        navigationItem.backBarButtonItem = UIBarButtonItem(title: "All Pubs", style: .plain, target: nil, action: nil)
        
        // set up the refresh controller, but only if we are on iOS 10
        if let iosVersion = Int(UIDevice.current.systemVersion.components(separatedBy: ".")[0]), iosVersion >= 10 {
            self.refreshControl = UIRefreshControl()
            self.refreshControl?.attributedTitle = NSAttributedString(string: "Checking for updates...")
            
            self.refreshControl?.addTarget(self, action: #selector(userInitiatedRefresh(sender:)), for: .valueChanged)
        }
        
        // set up the search results controller
        searchController.searchResultsUpdater = self
        searchController.dimsBackgroundDuringPresentation = false
        definesPresentationContext = true
        setupSearchBar(searchBar: searchController.searchBar)

        applySortAndFilters()
    }
    
    // This sets up the closures of the reachability object
    // It sets the isConnectedToNetwork flag when the status changes
    func setupReachability() {
        reachability?.whenReachable = { _ in
            DispatchQueue.main.async {
                print("Network is reachable")
                self.isConnectedToNetwork = true
                self.tableView.reloadData()
            }
        }
        reachability?.whenUnreachable = { _ in
            DispatchQueue.main.async {
                print("Network is unreachable")
                self.isConnectedToNetwork = false
                self.tableView.reloadData()
            }
        }
        do {
            try reachability?.startNotifier()
        } catch {
            print("Unable to start Reachability notifier")
        }
    }
    
    // Finds the table view cell containing the given item
    // This must ONLY be called with an object known to be in a cell
    func getContainingCell(_ item: UIView) -> UITableViewCell {
        // repeatidly go up the superview chain until we get to a TableViewCell
        // This will be the cell which contains the view
        var tvc = item
        repeat {
            tvc = tvc.superview!
        } while ((tvc as? UITableViewCell) == nil)
        
        return tvc as! UITableViewCell
    }

    
    func userInitiatedRefresh(sender: Any) {
        pubsManager.checkForUpdates { count, _ in
            DispatchQueue.main.async {
                self.refreshControl?.endRefreshing()
            }
        } 
    }

    
    func setupSearchBar(searchBar: UISearchBar) {
        tableView.tableHeaderView = searchBar
    }
    
    // MARK: UITableViewDataSurce UITableViewDelegate
    
    // The number of sections is how many arrays in the visiblePubs matrix
    override func numberOfSections(in tableView: UITableView) -> Int {
        return visiblePublications.count
    }
    
    // When the table is sorted by publication, the sections are titled for each type
    // When the table isn't, there isn't any section title (return empty string)
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            let numVisible = visiblePublications.map { $0.count }.reduce(0, { $0 + $1 })
            if numVisible == 0 {
                return "Nothing matches - try a different search or filter"
            }
        }
        
        if sortFilterOptions.sortMethod == .byType {
            if visiblePublications[section].count > 0 {
                return sortFilterOptions.typeSortOrder[section].type
            } else {
                return ""
            }
        } else {
            return ""
        }
    }
    
    // Returns the number of publications to put in each section
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return visiblePublications[section].count
    }
    
    // Loads and configures the cell, based off of the pub returned by getPubForIndex
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier,
                                                 for: indexPath) as! PublicationTableViewCell
        
        let publication = getPubForIndex(indexPath)
        cell.setupCell(publication: publication)
        cell.downloadStatus.delegate = self
        
        // disable the download button if there is no connection, and if the download button is the download button
        // and not the open button
        //cell.downloadOpenButton.isEnabled = true
        if !isConnectedToNetwork && publication.status == .NotDownloaded {
            //cell.downloadOpenButton.isEnabled = false
        }
        
        return cell
    }
    
    // Allow the user to swipe to delete a local publication
    // We will only delete the local file (via the pub manager), it will not remove the pub from the db
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle,
                            forRowAt indexPath: IndexPath) {
        let pub = getPubForIndex(indexPath)
        if pub.status == .IsDownloaded && editingStyle == .delete {
            pubsManager.deleteEpub(pub)
            deletePubRow(at: indexPath)
        }
    }
    
    // default is to just reload the row. Override to implement deleting the row (ie, if showing only downloaded pubs)
    func deletePubRow(at indexPath: IndexPath) {
        tableView.reloadRows(at: [indexPath], with: .none)
    }
    
    // Allows the Delete behavior only if the pub is downloaded
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        let pub = getPubForIndex(indexPath)
        return (pub.status == .IsDownloaded)
    }
    
    func getPubForIndex(_ indexPath: IndexPath) -> Publication {
        return visiblePublications[indexPath.section][indexPath.row]
    }
    
    func getVisibleIndex(forPub: Publication) -> IndexPath? {
        // loop over all the pubs - if we find a match, return that index path
        for (section, pubsByType) in self.visiblePublications.enumerated() {
            for (row, pub) in pubsByType.enumerated() {
                if forPub == pub {
                    return IndexPath(row: row, section: section)
                }
            }
        }
        
        return nil
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let detailVC = PublicationViewController()
        detailVC.pub = getPubForIndex(indexPath)
        detailVC.navigationItem.leftBarButtonItem = splitViewController?.displayModeButtonItem
        detailVC.navigationItem.leftItemsSupplementBackButton = true
        let detailNav = UINavigationController(rootViewController: detailVC)
 
        showDetailViewController(detailNav, sender: self)
    }
    
    // MARK: Actions
    
    func filterSelect(_ sender: UISegmentedControl) {
        if sender.selectedSegmentIndex == 0 {
            // all publications
            visiblePublicationsStatus = .all
        } else if sender.selectedSegmentIndex == 1 {
            // downloaded publications
            visiblePublicationsStatus = .local
            
        }
        tableView.reloadData()
    }
    
    func settingsPressed(_ sender: UIBarButtonItem) {
        let settingsView = SettingsViewController()
        presentAsPopover(settingsView, sender: sender)
    }
    
    func sortFilterPressed(_ sender: UIBarButtonItem) {
        let sortFilter = SortFilterViewController(options: sortFilterOptions)
        sortFilter.delegate = self
        presentAsPopover(sortFilter, sender: sender)
    }
    
    // MARK: PublicationManagerDelegate
    
    // reloads all the publications in response to the manager telling us that there are new publications
    func didAddPublications() {
        DispatchQueue.main.async {
            print("Did add publications")
            self.applySortAndFilters()
            self.tableView.reloadData()
            print("Data reloaded")
        }
    }
    
    // MARK: PublicationManagerDelegate
    // reloads all data. This ensures that it works properly in the Master when only local pubs are shown
    func didFinishDownloadingEpub(pub: Publication) {
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }
    
    // shows an alert about a failed download
    func downloadFailed(pub: Publication) {
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }
    
    // Updates the cell with the new download progress
    func downloadProgress(pub: Publication, progress: Float) {
        DispatchQueue.main.async {
            guard let path = self.getVisibleIndex(forPub: pub) else {
                return
            }
            
            guard let cell = self.tableView.cellForRow(at: path) as? PublicationTableViewCell else {
                return
            }
            
            cell.setProgress(progress: progress)
        }
    }
    
    // MARK: Searching
    func updateSearchResults(for searchController: UISearchController) {
        guard let searchText = searchController.searchBar.text else {
            prevSearchText = ""
            applySortAndFilters()
            return
        }
        
        if searchText == "" {
            applySortAndFilters()
        } else {
            // reset the visible publications in the event that the new searchText is shorter than the previous
            // ie - user pressed backspace
            if searchText.characters.count < prevSearchText.characters.count {
                applySortAndFilters()
            }
            applySearchFilter(searchText)
        }
        prevSearchText = searchText
        tableView.reloadData()
    }
    
    // applies the search filter
    func applySearchFilter(_ searchText: String) {
        let words = searchText.components(separatedBy: " ")
        for word in words {
            visiblePublications = visiblePublications.map {
                $0.filter("title CONTAINS[c] %@ OR abstract CONTAINS[c] %@ OR terms CONTAINS[c] %@", word, word, word)
            }
        }
    }
    
    // MARK: Filtering
    
    // Applies the currently selected filters to the visible publications list
    func applySortAndFilters() {
        // first set up the desired sort
        switch sortFilterOptions.sortMethod {
        case .byType:
            visiblePublications = publicationsByType
        case .byDate:
            visiblePublications = [allPublications.sorted(byKeyPath: "datePublished",
                                                          ascending: !sortFilterOptions.sortDescendingDates)]
        }
        
        // select the correct download status
        filterByDownloadedStatus()
        
        // now apply filters to each section of the visiblePublications array, using maps
        if sortFilterOptions.filterByDate {
            visiblePublications = visiblePublications.map {
                $0.filter("datePublished >= %@", sortFilterOptions.filterDate!)
            }
        }
        
        if sortFilterOptions.filterByType {
            visiblePublications = visiblePublications.map {
                $0.filter("type == %@", sortFilterOptions.typeFilter)
            }
        }
        
        //if prevSearchText != "" {
        //    applySearchFilter(prevSearchText)
        //}
        
        tableView.reloadData()
        
    }
    
    // filters the visible publications by their download status (visiblePublicationsStatus)
    func filterByDownloadedStatus() {
        if visiblePublicationsStatus == .local {
            visiblePublications = visiblePublications.map {
                $0.filter("_status == %@", Publication.PubStatus.IsDownloaded.rawValue)
            }
        }
    }
    
    // presents the passed viewController as a pop-over, if the device allows (ie on iPad only)
    func presentAsPopover(_ viewController: UIViewController, sender: UIBarButtonItem) {
        viewController.modalPresentationStyle = .popover
        if let popover = viewController.popoverPresentationController {
            popover.barButtonItem = sender
        }
        present(viewController, animated: true, completion: nil)
    }
    
 
    // MARK: SortFilterDelegate
    
    // called when the user exits the SortFilter dialog. Updates the sort options
    func updateSortFilterOptions(_ options: SortFilterOptions) {
        sortFilterOptions = options
        sortFilterOptions.save()
        let topRow = IndexPath(row: 0, section: 0)
        tableView.scrollToRow(at: topRow, at: .top, animated: true)
        applySortAndFilters()
    }
    
    // MARK: DownloadStatusDelegate
    
    func downloadTouched(sender: DownloadStatusView) {
        let cell = getContainingCell(sender)
        if let index = tableView.indexPath(for: cell) {
            let pub = getPubForIndex(index)
            findActionHander()?.download?(pub: pub)
            tableView.reloadRows(at: [index], with: .none)
        }
    }
    
    func openTouched(sender: DownloadStatusView) {
        let cell = getContainingCell(sender)
        if let index = tableView.indexPath(for: cell) {
            let pub = getPubForIndex(index)
            
            findActionHander()?.open?(pub: pub)
        }
    }
    
    func findActionHander() -> PublicationActions? {
        var currentVC: UIViewController? = self
        while currentVC != nil && !(currentVC is PublicationActions) {
            currentVC = currentVC?.parent
        }
        
        if let currentVC = currentVC, let handler = currentVC as? PublicationActions {
            return handler
        } else {
            return nil
        }
    }
    
}
