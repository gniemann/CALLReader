//
//  PublicationViewController.swift
//  CALL
//
//  Created by Gregory Niemann on 5/11/17.
//  Copyright © 2017 Greg Niemann. All rights reserved.
//

import UIKit

class PublicationViewController: UIViewController, DownloadStatusViewDelegate {

    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var publishedLabel: UILabel!
    @IBOutlet weak var coverPhoto: UIImageView!
    @IBOutlet weak var initialDescriptionLabel: UILabel!
    @IBOutlet weak var expandedDescriptionLabel: UILabel!
    @IBOutlet weak var similarScrollView: UIScrollView!
    @IBOutlet weak var notesTextView: UITextView!
    @IBOutlet weak var downloadStatus: DownloadStatusView!
    @IBOutlet weak var expandedDescirptionHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var similarPubsView: UIView!
    
    var pub: Publication!
    var hasSetExpandedText = false
    
    var oldContentInset: UIEdgeInsets?
    var oldIndicatorInset: UIEdgeInsets?
    var oldOffset: CGPoint?
    
    var documentController: UIDocumentInteractionController?
    var actionBarItem: UIBarButtonItem!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        titleLabel.text = pub.title
        publishedLabel.text = "Published \(pub.datePublishedString)"
        coverPhoto.image = pub.coverImage
        notesTextView.text = pub.notes
        
        initialDescriptionLabel.text = pub.abstract
        
        downloadStatus.status = pub.status
        downloadStatus.delegate = self
        
        if pub.similar.isEmpty {
            similarPubsView.isHidden = true
        } else {
            setupSimilarScroll()
        }
        
        title = pub.title
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardShow(notification:)),
                                               name: NSNotification.Name.UIKeyboardWillShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDismissed(notification:)),
                                               name: NSNotification.Name.UIKeyboardDidHide, object: nil)
        
        setupActionButton()
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        PublicationManager.shared.write {
            pub.notes = notesTextView.text
        }
    }
    
    func setupSimilarScroll() {
        if pub.similar.count < 1 {
            return
        }
        
        let imageWidth = similarScrollView.frame.width / 2
        let imageHeight = imageWidth * (84 / 65)
        
        let scrollContents = UIView()
        scrollContents.translatesAutoresizingMaskIntoConstraints = false
        
        var constraints = [NSLayoutConstraint]()
        constraints.append(scrollContents.heightAnchor.constraint(equalToConstant: (imageHeight + 8)))
        constraints.append(similarScrollView.heightAnchor.constraint(equalTo: scrollContents.heightAnchor))
        
        var leftAnchor = scrollContents.leadingAnchor
        
        for similar in pub.similar {
            let simCoverView = UIButton()
            simCoverView.setImage(similar.coverImage, for: .normal)
            simCoverView.tag = similar.id
            simCoverView.addTarget(self, action: #selector(similarTouched(sender:)), for: .touchUpInside)
            
            simCoverView.translatesAutoresizingMaskIntoConstraints = false
            constraints.append(contentsOf: [simCoverView.heightAnchor.constraint(equalToConstant: imageHeight),
                                            simCoverView.widthAnchor.constraint(equalToConstant: imageWidth)])
            
            simCoverView.layer.borderWidth = 2
            let leadingAnchor = simCoverView.leadingAnchor.constraint(equalTo: leftAnchor, constant: 8)
            leftAnchor = simCoverView.trailingAnchor
            constraints.append(leadingAnchor)
            scrollContents.addSubview(simCoverView)
            
            // add top and bottom constraints
            constraints.append(contentsOf: [simCoverView.topAnchor.constraint(equalTo: similarScrollView.topAnchor, constant: 4),
                                            simCoverView.bottomAnchor.constraint(equalTo: similarScrollView.bottomAnchor, constant: -4)])
        }
        
        constraints.append(scrollContents.trailingAnchor.constraint(equalTo: leftAnchor, constant: 8))
        
        similarScrollView.addSubview(scrollContents)
        constraints.append(contentsOf: [scrollContents.leadingAnchor.constraint(equalTo: similarScrollView.leadingAnchor),
                                        scrollContents.trailingAnchor.constraint(equalTo: similarScrollView.trailingAnchor),
                                        scrollContents.topAnchor.constraint(equalTo: similarScrollView.topAnchor),
                                        scrollContents.bottomAnchor.constraint(equalTo: similarScrollView.bottomAnchor)])
        NSLayoutConstraint.activate(constraints)
        
        similarScrollView.layer.borderWidth = 0.5
        similarScrollView.layer.borderColor = UIColor.black.cgColor
        similarScrollView.layer.cornerRadius = 2
    }
    
    func setupActionButton() {
        if pub.status == .IsDownloaded && actionBarItem == nil {
            actionBarItem = UIBarButtonItem(barButtonSystemItem: .action, target: self,
                                            action: #selector(actionButtonPressed(_:)))
            navigationItem.rightBarButtonItem = actionBarItem
        }
    }
    
    func similarTouched(sender: UIButton) {
        let pubID = sender.tag
        if let similar = PublicationManager.shared.getPub(with: pubID) {
            let similarVC = PublicationViewController()
            similarVC.pub = similar
            navigationController?.pushViewController(similarVC, animated: true)
        }
    }
    
    override func viewWillLayoutSubviews() {
        layoutDescriptions()
    }
    
    func layoutDescriptions() {
        if initialDescriptionLabel.isTruncated() {
            let trucationIdx = initialDescriptionLabel.findTruncationIndex()
            let index = pub.abstract.index((pub.abstract.startIndex), offsetBy: trucationIdx)
            expandedDescriptionLabel.text = pub.abstract.substring(from: index)
            expandedDescriptionLabel.isHidden = false
        } else {
            expandedDescriptionLabel.isHidden = true
            expandedDescriptionLabel.text = ""
        }
        
        expandedDescriptionLabel.sizeToFit()
        expandedDescirptionHeightConstraint.constant = expandedDescriptionLabel.intrinsicContentSize.height
    }

    func downloadTouched(sender: DownloadStatusView) {
        findActionHandler()?.download?(pub: pub)
        downloadStatus.status = pub.status
    }
    
    func openTouched(sender: DownloadStatusView) {
        findActionHandler()?.open?(pub: pub)
    }
    
    func findActionHandler() -> PublicationActions? {
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
    
    func keyboardShow(notification: Notification) {
        oldContentInset = scrollView.contentInset
        oldIndicatorInset = scrollView.scrollIndicatorInsets
        oldOffset = scrollView.contentOffset
        
        if let dict = notification.userInfo,
            let rect = dict[UIKeyboardFrameEndUserInfoKey] as? NSValue {
            let keyboardRect = scrollView.convert(rect.cgRectValue, from: nil)
            scrollView.contentInset.bottom = keyboardRect.size.height
            scrollView.scrollIndicatorInsets.bottom = keyboardRect.size.height
            
            scrollView.scrollRectToVisible(keyboardRect, animated: true)
        }
    }
    
    func keyboardDismissed(notification: Notification) {
        if let oldContentInset = self.oldContentInset,
            let oldOffset = self.oldOffset,
            let oldIndicatorInset = self.oldIndicatorInset {
            scrollView.contentInset = oldContentInset
            scrollView.bounds.origin = oldOffset
            scrollView.scrollIndicatorInsets = oldIndicatorInset
        }
    }
    
    func actionButtonPressed(_ sender: UIBarButtonItem) {
        let pubURL = URL(fileURLWithPath: pub.epubPath)
        
        documentController = UIDocumentInteractionController(url: pubURL)
        documentController?.presentOptionsMenu(from: actionBarItem, animated: true)
    }

}

extension PublicationViewController: PublicationManagerDelegate {
    func didAddPublications() {
        
    }
    
    func didFinishDownloadingEpub(pub: Publication) {
        if self.pub == pub {
            DispatchQueue.main.async {
                self.downloadStatus.status = pub.status
                self.setupActionButton()
            }
        }
    }
    
    func downloadFailed(pub: Publication) {
        if self.pub == pub {
            DispatchQueue.main.async {
                self.downloadStatus.status = pub.status
            }
        }
    }
    
    func downloadProgress(pub: Publication, progress: Float) {
        if self.pub == pub {
            DispatchQueue.main.async {
                self.downloadStatus.setProgress(progress: progress)
            }
        }
    }
}



// this extention allows strings to determine how much height a given label requires
// required for determining the truncation point
extension String  {
    func getReqHeight(inLabel label: UILabel) -> CGFloat {
        let fullSize: CGSize = (self as NSString).boundingRect(
            with: CGSize(width: label.frame.size.width, height: CGFloat.greatestFiniteMagnitude),
            options: NSStringDrawingOptions.usesLineFragmentOrigin,
            attributes: [NSFontAttributeName: label.font],
            context: nil).size
        return fullSize.height
    }
}

// an extention to a UILabel to check to see if it is truncated
// inspired from Stack Overflow https://stackoverflow.com/questions/3077109/how-to-check-if-uilabel-is-truncated
extension UILabel {
    func isTruncated() -> Bool {
        if let string = self.text {
            let fullHeight = string.getReqHeight(inLabel: self)
            return (fullHeight > self.bounds.size.height)
        }
        // no text, cannot be truncated
        return false
    }
    
    // This finds the point in the string that truncation occurs. We can use it to expand the rest of the text
    func findTruncationIndex() -> Int {
        if !self.isTruncated() {
            return -1
        }
        guard let str = text else {
            print("No text")
            return -1
        }
        
        let words = str.components(separatedBy: " ")
        
        var string = words[0]
        let wordCount = words.count
        var wordIdx = 0
        var strLen = string.characters.count
        
        while wordIdx < wordCount && string.getReqHeight(inLabel: self) < self.bounds.size.height {
            // not truncated yet, add another word
            wordIdx = wordIdx + 1
            string = string + " " + words[wordIdx]
            strLen = strLen + 1 + words[wordIdx].characters.count
            
        }
        strLen = strLen - 1 - words[wordIdx].characters.count
        var index = str.index(str.startIndex, offsetBy: strLen)
        while strLen > 1 && str.characters[index] != " " {
            index = str.index(index, offsetBy: -1)
            strLen -= 1
        }
        
        return strLen + 1
        
    }
}
