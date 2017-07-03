/*
  SortFilterOptions.swift
  CALL

  Created by Gregory Niemann on 1/11/17.
  Copyright © 2017 Greg Niemann. All rights reserved.

 class SortFilterOptions - represents available methods of sorting and filtering publications
 
 On init, reads the current options from the UserDefaults. Sets them to resonable settings if this is the first run
 
 TODO: There is really only one sort method - sorting by date published (ascending or descending). The other method
   is more of a grouping - it groups by type, and within that group, sorts by date published
 
  typeFilter is set to the single type to display. 
 
 dateFilter is set to the earliest published date to display - ie it will display all after whatever date it is
 
*/

import UIKit


class SortFilterOptions {
    
    enum SortMethods: Int {
        case byDate = 0
        case byType
    }
    
    static var sortMethodTitles = ["Date Published", "Publication type"]
    
    var sortMethod: SortMethods = .byType
    var typeSortOrder: [PublicationType]
    var sortDescendingDates = true
    
    var filterByType = false
    var filterByDate = false
    
    var typeFilter: PublicationType? {
        didSet {
            if typeFilter != nil {
                filterByType = true
            } else {
                filterByType = false
            }
        }
    }
    var filterDate: Date? {
        didSet {
            if filterDate != nil {
                filterByDate = true
            } else {
                filterByDate = false
            }
        }
    }
    
    init() {
        // retrieve any stored settings from the UserDefaults settings
        let defaults = UserDefaults.standard
        sortMethod = SortFilterOptions.SortMethods(rawValue: defaults.integer(forKey: "SortMethod"))!
        filterByDate = defaults.bool(forKey: "FilterByDate")
        filterDate = defaults.object(forKey: "FilterDate") as? Date
        sortDescendingDates = defaults.bool(forKey: "DescendingDates")
        
        filterByType = defaults.bool(forKey: "FilterByType")
        let type = defaults.string(forKey: "TypeFilter")
        
        typeFilter = PublicationManager.shared.publicationTypes.filter("type = %@", type ?? "Handbooks").first
        
        let storedSortOrder = defaults.array(forKey: "GroupByOrder") as! [String]
        typeSortOrder = storedSortOrder.map { PublicationManager.shared.publicationTypes.filter("type = %@", $0).first! }
    }
    
    // saves all values to the UserDefaults store
    func save() {
        let defaults = UserDefaults.standard
        defaults.set(sortMethod.rawValue, forKey: "SortMethod")
        defaults.set(filterByDate, forKey: "FilterByDate")
        defaults.set(filterByType, forKey: "FilterByType")
        defaults.set(sortDescendingDates, forKey: "DescendingDates")
        
        if filterByDate {
            defaults.set(filterDate, forKey: "FilterDate")
        }
        if filterByType {
            defaults.set(typeFilter?.type, forKey: "TypeFilter")
        }
        
        let storedSortOrder = typeSortOrder.map { $0.type }
        defaults.set(storedSortOrder, forKey: "GroupByOrder")
        defaults.synchronize()
    }
    
}
