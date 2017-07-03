//
//  Publication.swift
//  CALL
//
//  Created by Greg Niemann on 10/8/16.
//  Copyright © 2016 Greg Niemann. All rights reserved.
//

import UIKit
import RealmSwift

/*
    PublicationType - table of publication types (handbook, newsletter, etc)
    Has a single field, type, which is also the primary key
*/
class PublicationType : Object {
    dynamic var type = ""
    
    override static func primaryKey() -> String {
        return "type"
    }
    
    override static func indexedProperties() -> [String] {
        return ["type"]
    }
}

/*
    Publication - represents a Publication
*/
class Publication : Object {
    // MARK: Types
    enum PubStatus : Int {
        case NotDownloaded = 0
        case Downloading
        case IsDownloaded
    }
    
    // MARK: Properties
    
    // MARK: database field properties
    dynamic var id = 0
    dynamic var title = ""
    dynamic var publicationURL = ""
    dynamic var abstract = ""
    dynamic var datePublished = Date()
    dynamic var _status = PubStatus.NotDownloaded.rawValue
    dynamic var _coverImage: Data? = nil
    dynamic var type: PublicationType?
    let similar = List<Publication>()
    dynamic var terms = ""
    dynamic var notes = ""
    
    // property which returns the path to the associated document (either an epub or pdf)
    var epubPath: String {
        let documentPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as String
        
        let alphaNumerics = CharacterSet.alphanumerics
        var filename = title
        
        for ch in title.unicodeScalars {
            if !alphaNumerics.contains(ch) && ch != "-" && ch != " " {
                filename = filename.replacingOccurrences(of: "\(ch)", with: "")
            }
        }
        
        filename = "\(filename).pdf"
        let filePath = "\(documentPath)/\(filename)"

        return filePath
    }
    
    // returns the current status - NotDownloaded, IsDownloaded or Downloaded
    var status: PubStatus {
        get {
            return PubStatus(rawValue: self._status)!
        }
        set(newStatus) {
            self._status = newStatus.rawValue
        }
    }
    
    // returns the cover image, as a UIImage
    var coverImage: UIImage? {
        if let data = self._coverImage {
            return UIImage(data: data)
        } else {
            return UIImage()
        }
    }
    
    // MARK: Database overrides
    override static func primaryKey() -> String? {
        return "id"
    }
    
    override static func ignoredProperties() -> [String] {
        return ["status"]
    }
    
    override static func indexedProperties() -> [String] {
        return ["title", "datePublished", "publicationURL"]
    }
    
    // updates this publication with data from the PublicationListing
    // This is useful both on creation and for updating
    func updatePub(listing: PublicationListing) {
        self.title = listing.title
        self.abstract = listing.abstract
        self.datePublished = listing.datePublished
        self.publicationURL = listing.publicationURL
        self.terms = listing.terms
    }
    
    var datePublishedString: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd MMM yy"
        return dateFormatter.string(from: self.datePublished)
    }
}

/*
    PublicationListing uses the Gloss library to decode JSON for a single publication from the updates file
    After creation, the fields will all be accessible
 
    Primary purpose for this class is to act as intermediary between the updates file and Publication object
*/
struct PublicationListing {
    let id: Int
    let title: String
    let abstract: String
    let datePublished: Date
    let coverImageURL: String
    let publicationURL: String
    let type: String
    var similar: [Int] = []
    var terms: String
    
    init?(json: [String: Any]) {
        guard let id = json["id"] as? Int,
            let title = json["title"] as? String,
            let abstract = json["abstract"] as? String,
            let coverImageURL = json["image_url"] as? String,
            let publicationURL = json["publication_url"] as? String,
            let datePublished = json["date_published"] as? String,
            let type = json["type"] as? String else {
                return nil
        }
        self.id = id
        self.title = title
        self.abstract = abstract
        self.coverImageURL = coverImageURL
        self.publicationURL = publicationURL
        self.type = type
        
        let dateFormat = DateFormatter()
        dateFormat.dateFormat = "yyyy-MM-dd"
        self.datePublished = dateFormat.date(from: datePublished) ?? Date()
        
        if let similar_ids = json["similar"] as? [Any] {
            for sim in similar_ids {
                if let sim = sim as? Int {
                    similar.append(sim)
                }
            }
        }
        
        self.terms = json["terms"] as? String ?? ""
    }
}

/*
 Gloss class for the overall updates file
 Sole purpose is to parse the file into a useable object
*/
class UpdateListing {
    let service: String
    let messages: [String]
    let publications: [PublicationListing]
    
    init?(json: [String: Any]) {
        service = json["service"] as? String ?? ""
        
        messages = (json["messages"] as? [String]) ?? []
        
        if let pubs = json["publications"] as? [[String: Any]] {
            let listings = pubs.map{ PublicationListing(json: $0) }
            publications = listings.filter { $0 != nil }.map { $0! }
        } else {
            publications = []
        }
    }
}

