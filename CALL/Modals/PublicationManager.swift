/*
  PublicationManager.swift
  CALL

  Created by Greg Niemann on 10/12/16.
  Copyright © 2016 Greg Niemann. All rights reserved.

class PublicationManager - this singleton manages the publication database, including retrieving updates 
 to the database and downloading individual pubs. It also ensures the underlying integrity of the database
 
    shared - the shared singleton instance of PublicationManager
    publications - a collection of all publications
    publicationTypes - a collection of all publication types
 
 
 
 
 
 protocol PublicationManagerDelegate - allows another class to receive notifications from the PublicationsManager
    didAddPublications - called when new publications are added to the database
    didFinishDownloadingEpub(pub:) - called when the document for pub has completed downloading
    downloadProgress(pub:progress:) - called periodically with an update (as a percentage) of the progress of download
 
 class Counter - a helper class, implements a rudimantary multi-thread counter.
 
 class PubsList - a helpter class, implements a rudimantary multi-thread list (of integers)

 
 */

import Foundation
import UIKit
import RealmSwift

protocol PublicationManagerDelegate: class {
    func didAddPublications()
    func didFinishDownloadingEpub(pub: Publication)
    func downloadFailed(pub: Publication)
    func downloadProgress(pub: Publication, progress: Float)
}

class PublicationManager : NSObject, URLSessionDelegate, URLSessionDownloadDelegate{
    
    // singleton instance
    static let shared = PublicationManager()
    
    weak var delegate: PublicationManagerDelegate?
    
    var realm: Realm!
    
    lazy var publications: Results<Publication> = self.realm.objects(Publication.self)
    lazy var publicationTypes: Results<PublicationType> = self.realm.objects(PublicationType.self).sorted(byKeyPath: "type")
    
    // the two URLSessions. updateSession is simply for retrieving meta-data updates. epubDownloadSession is 
    // for downloading publications, and is background-able
    lazy var updateSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config)
    }()
    lazy var epubDownloadSession: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: "CALL-epub")
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    
    var pendingUpdates = 0
    var lastUpdateStr = "Wed, 01 Feb 2017 01:35:58 GMT"
    var serviceURL = URL(string: "https://airborne.herokuapp.com/static/call/pubs.json")!
    
    // MARK: Archive Paths
    static let DocumentsDirectory = FileManager().urls(for: .documentDirectory, in: .userDomainMask).first!
    static let SettingsURL = DocumentsDirectory.appendingPathComponent("settings")
    
    override init() {
        super.init()
        
        self.realm = try! Realm()
        
        // attempt to read the last update and service URLs from the settings file. If it fails, the already set 
        // defaults will be used (useful for first time app is run)
        do {
            let settingsData = try Data(contentsOf: PublicationManager.SettingsURL)
            let unarchiver = NSKeyedUnarchiver(forReadingWith: settingsData)
            
            if let lastUpdate = unarchiver.decodeObject(forKey: "LastUpdate") as? String {
                lastUpdateStr = lastUpdate
            }

            if let urlString = unarchiver.decodeObject(forKey: "ServiceURL") as? String {
                serviceURL = URL(string: urlString)!
            }
            unarchiver.finishDecoding()
        } catch {
            print("Cannot open settings file")

        }
        
    }
    
    // saves the service URL and last update string to the settings file. Called after successful updates
    func saveSettings() {
        let settingsData = NSMutableData()
        let archiver = NSKeyedArchiver(forWritingWith: settingsData)
        archiver.encode(serviceURL.absoluteString, forKey: "ServiceURL")
        archiver.encode(lastUpdateStr, forKey: "LastUpdate")
        archiver.finishEncoding()
        settingsData.write(to: PublicationManager.SettingsURL, atomically: true)
    }
    
    // adds pub to the publications database
    func add(pub: Publication) {
        do {
            try realm.write {
                realm.add(pub)
            }
        } catch {
            print("Error! Could not add publication")
        }
    }
    
    // initiates a download of the publication for the pub with the associated ID
    func downloadEpub(forPubWithID: Int) {
        print("Downloading epub")
        guard let requestedPub = realm.objects(Publication.self).filter("id == %@", forPubWithID).first else {
            print("Requsted pub does not exist")
            return
        }

        guard let url = URL(string: requestedPub.publicationURL) else {
            print("Invalid URL \(requestedPub.publicationURL)")
            return
        }
        
        // start a new download task, and change the pub's status to reflect
        let downloadTask = epubDownloadSession.downloadTask(with: url)
        do {
            try realm.write {
                requestedPub.status = .Downloading
            }
            downloadTask.resume()
        } catch {
            print("Error, could not set pub status. Download aborted")
        }
    }
    
    func downloadEpub(pub: Publication) {
        downloadEpub(forPubWithID: pub.id)
    }
    
    // retrieve the remote updates file and handles any required updates. completionHandler is called when complete
    // this is a highly async function. The function returns immediately, but the updates happen in a separate 
    // dispatch queue. completionHandler won't be called until all updates are retrieved, including downloading new 
    // image files (if required).
    // The first argument to completionHandler is the number of new publications. If an error occurred, this is set to 
    // -1. 0 indicates no new publications.
    // The second argument is a list of the pub IDs for the new pubs
    func downloadUpdates(completionHandler: @escaping ((Int, [Int])->Void)) {
        DispatchQueue.global(qos: .userInitiated).async {
            print("Downloading updates")
            let updateGroup = DispatchGroup()
            
            let counter = Counter()
            let newPubs = PubsList()
            var didUpdateSucced = true
            var updateStr = ""
            updateGroup.enter()
            let downloadTask = self.updateSession.dataTask(with: self.serviceURL) {
                data, res, error in
                
                guard let response = res as? HTTPURLResponse else {
                    print("Something is wrong - response not HTTPURLResponse")
                    didUpdateSucced = false
                    updateGroup.leave()
                    return
                }
                
                // first check two failure conditions (network failure or unintelligable response)
                // do this before we update the lastUpdated timestamp
                if !self.wasDownloadSuccessful(error: error, response: response) {
                    print("Update failed!")
                    didUpdateSucced = false
                    updateGroup.leave()
                    return
                }
                
                var jsonData: [String: Any]?
                do {
                    jsonData = try JSONSerialization.jsonObject(with: data!) as? [String: Any]
                } catch {
                    print("Error loading JSON")
                    completionHandler(-1, [])
                    updateGroup.leave()
                    return
                }
        
                guard let updatesListings = UpdateListing(json: jsonData!) else {
                    print("Error parsing JSON")
                    completionHandler(-1, [])
                    updateGroup.leave()
                    return
                }
            
                if let newService = URL(string: updatesListings.service) {
                    self.serviceURL = newService
                }
                
                // update the lastUpdate date, and save it, since we know the update succeeded
                updateStr = response.allHeaderFields["Date"] as! String
                
                let newPubsListings = updatesListings.publications
                
                print("Processing \(newPubsListings.count) listings")
                for pubListing in newPubsListings {
                    updateGroup.enter()
                    self.updatePub(pubListing) { success, isNew in
                        if !success {
                            didUpdateSucced = false
                        }
                        if isNew {
                            counter.increment()
                            newPubs.add(pubListing.id)
                        }
                        updateGroup.leave()
                    }
                }
                
                self.deleteRemovedListings(pubListings: newPubsListings)
                
                updateGroup.leave()
            }
            
            // turn on the network indicator and initiate the download
            UIApplication.shared.isNetworkActivityIndicatorVisible = true
            downloadTask.resume()
            
            // wait for all the parts of the update to finish before turning off the network indicator
            // this blocks this thread - but it's a background thread
            updateGroup.wait()
            UIApplication.shared.isNetworkActivityIndicatorVisible = false
            print("Updates complete")
            
            if didUpdateSucced {
                // if successful, save the date of this update and the new service. Then call the completion handler
                self.lastUpdateStr = updateStr
                self.saveSettings()
                completionHandler(counter.count, newPubs.list)
                if counter.count > 0 {
                    self.delegate?.didAddPublications()
                }
            } else {
                print("Download not successful")
                completionHandler(-1, [])
            }
            
            
            
            // uncomment to save the Realm file for bundling
            //self.writeDatabaseToFile()
        }
    }
    
    // removes publications that are no longer listed
    func deleteRemovedListings(pubListings: [PublicationListing]) {
        let currentIDs: Set<Int> = Set(pubListings.map { $0.id } )
        DispatchQueue.main.async {
            for p in self.publications {
                // find all non-current pubs and delete them
                if !currentIDs.contains(p.id) {
                    try! self.realm.write {
                        // remove all references to this pub in other similars
                        for otherPubs in p.similar {
                            if let idx = otherPubs.similar.index(of: p) {
                                otherPubs.similar.remove(objectAtIndex: idx)
                            }
                        }
                        // delete this pub
                        self.realm.delete(p)
                    }
                }
            }
        }
    }
    
    // writes the realm database to a separate file. This is used to create the database for the initial bundle
    func writeDatabaseToFile() {
        DispatchQueue.main.async {
            let filename = PublicationManager.DocumentsDirectory.appendingPathComponent("database.realm")
            if !FileManager.default.fileExists(atPath: filename.path) {
                try! self.realm.writeCopy(toFile: filename, encryptionKey: nil)
            }
        }
    }
    
    // updates a single pub with the data from PublicationListing
    // If the publication does not yet exist, it is created. If either the pub doesn't exist, or it's image data is nil,
    // image data is downloaded and stored
    // If the type is not known, it is added to the PublicationType table
    // completionHandler is called when complete (to include downloading the image). The first arguement is whether 
    // the update was successful. The second is whether this is a new publication (true) or an existing one (false)
    func updatePub(_ pubListing: PublicationListing, completionHandler: @escaping ((Bool, Bool) -> Void)) {
        DispatchQueue.main.async {
            // check to see if this is an update, or new
            var pub_obj = self.publications.filter("id = %@", pubListing.id).first
            
            if pub_obj == nil {
                pub_obj = Publication(value: ["id": pubListing.id])
            }
            
            guard let pub = pub_obj else {
                print("Error obtaining pub")
                completionHandler(false, false)
                return
            }
            
            // look up the type
            var typeObj = self.publicationTypes.filter("type == %@", pubListing.type).first
            
            if typeObj == nil {
                // need to make a new type for this publication
                typeObj = PublicationType(value: ["type": pubListing.type])
                do {
                    try self.realm.write {
                        self.realm.add(typeObj!, update: true)
                    }
                } catch {
                    print("Error, unable to add new type")
                    completionHandler(false, false)
                }
            }
            
            guard let type = typeObj else {
                print("Error obtaining type")
                completionHandler(false, false) // return the error
                return
            }
            
            do {
                try self.realm.write {
                    // do the updates:
                    pub.title = pubListing.title
                    pub.abstract = pubListing.abstract
                    pub.datePublished = pubListing.datePublished
                    pub.publicationURL = pubListing.publicationURL
                    pub.terms = pubListing.terms
                    pub.type = type
                    
                    // link the similar pubs on both ends (since one will always have been added before the other)
                    // must do this in the write block since it is also modifying the other side
                    for similarPubID in pubListing.similar {
                        if let similarPub = self.publications.filter("id == %@", similarPubID).first,
                            !pub.similar.contains(similarPub){
                            pub.similar.append(similarPub)
                            similarPub.similar.append(pub)
                        }
                    }
                    
                    self.realm.add(pub, update: true)
                }
            } catch {
                print("Error writing to database")
                completionHandler(false, false)
                return
            }
            
            // add cover data, if it's new (or for some reason we didn't get it last time
            if pub._coverImage == nil {
                self.downloadPubImage(forListing: pubListing, pub: pub) { success in
                    completionHandler(true, success)
                }
            } else {
                completionHandler(true, false)
            }
        }
        
    }
    
    // downloads the publication image and saves it to pub. Calls completionHandler when complete. completionHandler's
    // argument is whether the download the successful
    func downloadPubImage(forListing pubListing: PublicationListing, pub: Publication, completionHandler: @escaping ((Bool) -> Void)) {
        guard let imageURL = URL(string: pubListing.coverImageURL) else {
            print("Bad Image URL")
            completionHandler(false)
            return
        }
        let imageDownload = self.updateSession.dataTask(with: imageURL) {
            data, response, error in
            
            if !self.wasDownloadSuccessful(error: error, response: response as? HTTPURLResponse) {
                print("Downloading cover image failed")
                print("URL: \(imageURL)")
                completionHandler(false)
                return
            }

            DispatchQueue.main.async {
                do {
                    try self.realm.write {
                        pub._coverImage = data
                    }
                    completionHandler(true)
                } catch {
                    print("Unable to write image data to database")
                    completionHandler(false)
                }
            }
        }
        imageDownload.resume()
    }
    
    // downloads updates without using a completion handler
    func downloadUpdates() {
        self.downloadUpdates {_, __ in
            return
        }
    }
    
    /* 
        Checks the remote updates file for changes since the last update, and if so, retrieves the updates.
        Uses HTTP HEAD method with header
        'If-Modified-Since' and response 304 (used cached version) to see if changes are available
        If updates are available, retrieves them, passing in completionHandler
        completionHandler is the handler to use for downloadUpdates. If no updates are available, it will call 
        with (0, []) to signify no updates
    */
    func checkForUpdates(completionHandler: @escaping ((Int, [Int])->Void)) {
        var headRequest = URLRequest(url: serviceURL)
        headRequest.httpMethod = "HEAD"
        headRequest.addValue(lastUpdateStr, forHTTPHeaderField: "If-Modified-Since")
        
        print("Sending HEAD request for updates: \(self.serviceURL)")
        let headTask = self.updateSession.dataTask(with: headRequest) {
            data, response, error in
            
            if let response = response as? HTTPURLResponse, self.wasDownloadSuccessful(error: error, response: response) {
                print("\(response.url)")
                print("HEAD status code = \(response.statusCode)")
                for header in response.allHeaderFields.keys {
                    print("\(header) - \(response.allHeaderFields[header])")
                }
                if response.statusCode == 304 {
                    // nothing new
                    print("Status 304 - no updates available")
                    completionHandler(0, [])
                }
                else {
                    // new updates are available
                    print("Updates available, downloading...")
                    self.downloadUpdates(completionHandler: completionHandler)
                }
            } else {
                // error, call completion with -1
                completionHandler(-1, [])
            }
        }
        headTask.resume()
    }
    
    // checkForUpdates without a completion handler
    func checkForUpdates() {
        self.checkForUpdates { _, __ in
            return
        }
    }
    
    // returns true if the download task was successful, based on the response
    func wasDownloadSuccessful(error: Swift.Error?, response: HTTPURLResponse?) -> Bool {
        if let error = error {
            print("Download failed with error: \(error.localizedDescription)")
            print(response?.url ?? "No URL")
            return false
        }
        
        if let response = response {
            if response.statusCode < 400 {
                return true
            } else {
                print("Download failed with response: \(response.statusCode)")
            }
        }
        
        return false
        
    }
    
    // MARK: Epub Downloading
    // called when a publication download is completed. Copies the file to the correct location and changes the pub's
    // status to downloaded
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // get the main queue since we are making accessing the model
        DispatchQueue.main.sync {
            // need the URL to get the pub, and need to know what pub before we check the status so we can reset the 
            // status if it failed
            guard let url = downloadTask.originalRequest?.url else {
                print("Problem with download task. Unable to get original request")
                return
            }
            
            guard let pub = self.publications.filter("publicationURL = %@", url.absoluteString).first else {
                print("Error, could not get publication")
                return
            }
            
            var success = true
            // check to ensure that the download was successful (a 404 will still return info)
            if !self.wasDownloadSuccessful(error: downloadTask.error, response: downloadTask.response as? HTTPURLResponse) {
                print("Download failed. Reverting status")
                success = false
            } else {
                // download successful. Copy the file to the correct path
                let localURL = URL(fileURLWithPath: pub.epubPath)
                
                let fileManager = FileManager.default
                
                do {
                    try fileManager.removeItem(at: localURL)
                } catch {
                    
                }
                
                // attempt to save the download to disk at the localURL
                do {
                    try fileManager.copyItem(at: location, to: localURL)
                } catch let error as NSError {
                    print("Could not save pub to disk: \(error.localizedDescription)")
                    success = false
                }
            }
            
            // if the download was successful, change the status of isDownloaded. If the save was not, revert to notDownloaded
            do {
                try self.realm.write {
                    if success {
                        pub.status = .IsDownloaded
                    } else {
                        pub.status = .NotDownloaded
                    }
                }
                print("Pub status updated")
            } catch {
                print("COULD NOT UPDATE PUBLICATION STATUS!")
            }
            
            if success {
                self.delegate?.didFinishDownloadingEpub(pub: pub)
            } else {
                self.delegate?.downloadFailed(pub: pub)
            }
        }
    }
    
    // determines which pub this download is for, and calls the delegate function downloadProgress with that pub 
    // and the percentage (from 0..1) of the download complete
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        
        guard let url = downloadTask.originalRequest?.url else {
            print("Big error")
            return
        }
        
        DispatchQueue.main.async {
            guard let pub = self.publications.filter("publicationURL = %@", url.absoluteString).first else {
                print("Could not get pub from URL")
                return
            }
            self.delegate?.downloadProgress(pub: pub, progress: progress)
        }
    }
    
    // if errors, revert the publication status to notDownloaded
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Swift.Error?) {
        if let error = error {
            print(error.localizedDescription)
            
            guard let url = task.originalRequest?.url else {
                print("Unable to get original URL on error")
                return
            }
            
            DispatchQueue.main.async {
                let pub = self.publications.filter("publicationURL = %@", url.absoluteString).first
                do {
                    try self.realm.write {
                        pub?.status = .NotDownloaded
                    }
                } catch {
                    print("Error, unable to update pub status")
                }
            }
        }

    }
    
    // Used for background refresh, calls the AppDelegate's completion handler to singify that we are done
    // downloading in the background
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            if let completionHandler = appDelegate.backgroundSessionCompletionHandler {
                appDelegate.backgroundSessionCompletionHandler = nil
                DispatchQueue.main.async {
                    completionHandler()
                }
            }
        }
    }
    
    /*
        Checks all publications to ensure that their status is correct
        First, ensures that pubs set as Downloaded are actually present. If the file isn't, the status is reverted
        Second, checks that pubs marked as Downloading have a download task associated. If not, their status is reverted
    */
    func validateIntegrity() {
        DispatchQueue.global(qos: .background).async {
            let backgroundRealm = try! Realm()
            let downloadedPubs = backgroundRealm.objects(Publication.self).filter("_status = %@",
                                                                            Publication.PubStatus.IsDownloaded.rawValue)
            let fileManager = FileManager.default
            for pub in downloadedPubs {
                // ensure that a downloadedPub's local file does exist
                if !fileManager.fileExists(atPath: pub.epubPath) {
                    print("Publication \(pub.title) not actually downloaded. Resetting status")
                    do {
                        try backgroundRealm.write {
                            pub.status = .NotDownloaded
                        }
                    } catch {
                        print("Error, unable to update publication status")
                    }
                }
            }
            
            // check all pubs with a status of DOWNLOADING
            let downloadingPubs = backgroundRealm.objects(Publication.self).filter("_status = %@",
                                                                            Publication.PubStatus.Downloading.rawValue)
            if downloadingPubs.count < 1 {
                // nothing currently thinks its downloading
                return
            }
            
            // pubs are in a downloading status. Check the current downloads and see if they are. If not, reset their status
            let pubURLs:[String] = downloadingPubs.map { $0.publicationURL }
            self.epubDownloadSession.getTasksWithCompletionHandler { _, __, downloadTasks in
                self.validateDownloadingPubs(pubURLs: pubURLs, downloadTasks: downloadTasks)
            }
            
        }
        
    }
    
    // validates that the URLs in pubsURLs are currently being downloaded (included in downloadTasks)
    // If not, looks up the pubs and revers their status
    func validateDownloadingPubs(pubURLs: [String], downloadTasks: [URLSessionDownloadTask]) {
        print("Searching for zombies...")
        var zombiePubURLs = [String]()
        for pubURL in pubURLs {
            var isFound = false
            for task in downloadTasks {
                if task.originalRequest?.url?.absoluteString == pubURL {
                    isFound = true
                    break
                }
            }
            if !isFound {
                zombiePubURLs.append(pubURL)
            }
            
        }
        
        // skip the rest if there are no zombies
        if zombiePubURLs.count < 1 {
            print("No zombies found")
            return
        } else {
            print("\(zombiePubURLs.count) zombies found")
        }
        
        let backgroundRealm = try! Realm()
        
        // find all the zombie pubs and reset their status
        let zombiePubs = backgroundRealm.objects(Publication.self).filter("publicationURL in %@", zombiePubURLs)
        do {
            try backgroundRealm.write {
                zombiePubs.forEach { $0.status = .NotDownloaded }
            }
        } catch {
            print("Error, something went wrong changing status to NotDownloaded")
        }
    }
    
    // deletes the publication file and sets the status as such. Does nothing else to the database record
    func deleteEpub(_ pub: Publication) {
        do {
            try FileManager.default.removeItem(atPath: pub.epubPath)
            try realm.write {
                pub.status = .NotDownloaded
            }
        } catch {
            print("Error, unable to delete pub")
        }
    }
    
    func getPub(with id: Int) -> Publication? {
        return publications.filter("id == %@", id).first
    }
    
    func write(_ transaction: ()->Void) {
        do {
            try realm.write {
                transaction()
            }
        } catch {
            print("Error, unavble to write transaction")
        }
    }

}

class Counter {
    var _cnt = 0
    private var queue = DispatchQueue(label: "counter_queue")
    var count: Int {
        return _cnt
    }
    
    func increment() {
        queue.sync {
            _cnt += 1
        }
    }
}

class PubsList {
    var _list = [Int]()
    private var queue = DispatchQueue(label: "pubslist_queue")
    var list: [Int] {
        return _list
    }
    
    func add(_ pub_id: Int) {
        queue.sync {
            _list.append(pub_id)
        }
    }
    
}
