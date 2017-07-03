//
//  PublicationTableViewCell.swift
//  CALL
//
//  Created by Gregory Niemann on 6/6/17.
//  Copyright © 2017 Greg Niemann. All rights reserved.
//

import UIKit

class PublicationTableViewCell: UITableViewCell {

    // MARK: Properties
    @IBOutlet weak var coverPhoto: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var publishedLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!
    @IBOutlet weak var downloadStatus: DownloadStatusView!

    @IBOutlet weak var leftStack: UIStackView!
    
    func setupCell(publication: Publication) {
        titleLabel.text = publication.title
        coverPhoto.image = publication.coverImage
        descriptionLabel.text = publication.abstract
        
        publishedLabel.text = "Published \(publication.datePublishedString)"
        
        downloadStatus.status = publication.status

    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
    }
    
    func setProgress(progress: Float) {
        downloadStatus.setProgress(progress: progress)
    }
}
