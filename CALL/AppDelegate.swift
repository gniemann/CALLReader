//
//  AppDelegate.swift
//  CALL
//
//  Created by Greg Niemann on 10/8/16.
//  Copyright © 2016 Greg Niemann. All rights reserved.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    
    var backgroundSessionCompletionHandler: (() -> Void)?


    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // get the working documents directory
        
        if let documentPath = FileManager().urls(for: .documentDirectory, in: .userDomainMask).first {
            print(documentPath.path)
            // do the first run check - if the database file doesn't exist, copy it from the bundle
            // also copy the lastupdate and serviceURL files
            let realmPath = documentPath.appendingPathComponent("default.realm")
            if !FileManager.default.fileExists(atPath: realmPath.path) {
                if let bundleRealmPath = Bundle.main.path(forResource: "seedDatabase", ofType: "realm") {
                    let bundleRealmURL = URL(fileURLWithPath: bundleRealmPath)
                    try! FileManager.default.copyItem(at:  bundleRealmURL, to: realmPath)
                }
            }
        }

        // Start downloading updates, if we're active
        // if we started due to a background refresh, don't call this as it duplicates
        // the network traffic
        if application.applicationState != .background {
            PublicationManager.shared.checkForUpdates()
            PublicationManager.shared.validateIntegrity()
        }
        
        // setup notifications and the Defaults dictionary
        setupNotifications(application)
        setupDefaults()
        
        // setup the window and root view controller (since we are not using a storyboard)
        window = UIWindow()
        window!.rootViewController = PublicationsSplitViewController()
        window!.backgroundColor = UIColor.white
        window!.makeKeyAndVisible()
        
        return true
    }
    
    // registers for background app refresh and local notifications
    func setupNotifications(_ application: UIApplication) {
        // set minimum time for background fetch to 1 day
        application.setMinimumBackgroundFetchInterval(60 * 60 * 24)

        
        // register for notifications
        let notificationSettings = UIUserNotificationSettings(types: [UIUserNotificationType.badge, UIUserNotificationType.alert], categories: nil)
        application.registerUserNotificationSettings(notificationSettings)
    }
    
    // set up the default settings, in case they haven't been set before
    func setupDefaults() {
        let defaults = UserDefaults.standard
        var notificationSettings = [String: Bool]()
        var autoDownloadSettings = [String: Bool]()
        var typeOrder = [String]()
        
        defaults.register(defaults: ["notifications": notificationSettings,
                                     "downloads": autoDownloadSettings,
                                     "SortMethod": SortFilterOptions.SortMethods.byDate.rawValue,
                                     "FilterByDate": false,
                                     "FilterByType": false,
                                     "DateFilter":  Date(),
                                     "TypeFilter": "Handbooks",
                                     "GroupByOrder": typeOrder,
                                     "DescendingDates": true])
        
        // get the previously set defaults
        notificationSettings = defaults.dictionary(forKey: "notifications") as! [String : Bool]
        autoDownloadSettings = defaults.dictionary(forKey: "downloads") as! [String : Bool]
        typeOrder = defaults.array(forKey: "GroupByOrder") as! [String]
        let knownTypes = Set<String>(notificationSettings.keys)
        
        // Add a default of notification but no autodownload for each type if that type isn't previously set
        for pubType in PublicationManager.shared.publicationTypes {
            if !knownTypes.contains(pubType.type) {
                notificationSettings[pubType.type] = true
                autoDownloadSettings[pubType.type] = false
                typeOrder.append(pubType.type)
            }
        }
        
        defaults.set(notificationSettings, forKey: "notifications")
        defaults.set(autoDownloadSettings, forKey: "downloads")
        defaults.set(typeOrder, forKey: "GroupByOrder")

        defaults.synchronize()
        
    }
    
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        backgroundSessionCompletionHandler = completionHandler
        _ = PublicationManager.shared.epubDownloadSession
    }

 
    func applicationDidBecomeActive(_ application: UIApplication) {
        // reset the badges to zero since the app has been opened by the user
        application.applicationIconBadgeNumber = 0
    }
    
    // background fetch
    func application(_ application: UIApplication,
                     performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        _ = PublicationManager.shared.epubDownloadSession
        PublicationManager.shared.checkForUpdates { result, newPubIDs in
            if result == -1 { // an error occurred
                completionHandler(.failed)
            } else if result == 0 { // nothing new - equate to noData
                completionHandler(.noData)
            } else { // new pubs to process
                self.processNewUpdates(application, newPubIDs: newPubIDs) {
                    completionHandler(.newData)
                }
            }
        }
    }
    
    // Processes new publications at the App Delegate level
    // Includes setting local notifications and beginning auto download (if enabled)
    func processNewUpdates(_ application: UIApplication, newPubIDs: [Int], completionHandler: @escaping () -> Void) {
        let defaults = UserDefaults.standard
        let notificationSettings = defaults.dictionary(forKey: "notifications") as? [String: Bool]
        let downloadSettings = defaults.dictionary(forKey: "downloads") as? [String: Bool]
        let pubManager = PublicationManager.shared
        
        // need the main queue since we reference the PublicationManager
        DispatchQueue.main.async {
            // only need to apply the badge icon if the app isn't running
            if application.applicationState == .background {
                application.applicationIconBadgeNumber += newPubIDs.count
            }
            for id in newPubIDs {
                if let pub = pubManager.publications.filter("id = %@", id).first, let type = pub.type?.type {
                    // send a notification if set and we're in the background
                    if let shouldNotify = notificationSettings?[type],
                        application.applicationState == .background && shouldNotify == true {
                        let notice = UILocalNotification()
                        notice.alertTitle = "New CALL Publication!"
                        notice.alertBody = "\(pub.title)\n\(pub.abstract)"
                        application.presentLocalNotificationNow(notice)
                    }
                    // autodownload regardless of where we are
                    if let shouldDownload = downloadSettings?[type], shouldDownload == true {
                        pubManager.downloadEpub(forPubWithID: id)
                    }
                }
            }
            
            completionHandler()
        }
    }

}


