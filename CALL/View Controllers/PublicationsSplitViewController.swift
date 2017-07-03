//
//  PublicationsSplitViewController.swift
//  CALL
//
//  Created by Gregory Niemann on 6/9/17.
//  Copyright © 2017 Greg Niemann. All rights reserved.
//

import UIKit
import PDFReader

@objc protocol PublicationActions {
    @objc optional func download(pub: Publication)
    @objc optional func open(pub: Publication)
}

class PublicationsSplitViewController: UISplitViewController, UISplitViewControllerDelegate,
        PublicationManagerDelegate, PublicationActions {

    let masterVC = MasterPublicationsViewController()
    lazy var loadingView = LoadingView()
    let pubsManager = PublicationManager.shared
    
    init() {
        super.init(nibName: nil, bundle: nil)
        
        let masterNav = UINavigationController(rootViewController: masterVC)
        
        let detailNav = UINavigationController()
        
        masterVC.applySortAndFilters()
        
        if let firstPub = masterVC.visiblePublications.first?.first {
            let detail = PublicationViewController()
            detail.pub = firstPub
            detail.navigationItem.leftBarButtonItem = displayModeButtonItem
            detailNav.pushViewController(detail, animated: false)
            
        }
        
        viewControllers = [masterNav, detailNav]
        delegate = self
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self
        PublicationManager.shared.delegate = self
    }
        
    // MARK: UISplitViewControllerDelegate
    
    func splitViewController(_ splitViewController: UISplitViewController, collapseSecondary secondaryViewController: UIViewController, onto primaryViewController: UIViewController) -> Bool {
        return true
    }
    
    // MARK: PublicationManager delegate
    
    func didAddPublications() {
        masterVC.didAddPublications()
    }
    
    func didFinishDownloadingEpub(pub: Publication) {
        masterVC.didFinishDownloadingEpub(pub: pub)
        
        func updateChildren(nav: UINavigationController) {
            for child in nav.childViewControllers {
                if let child = child as? UINavigationController {
                    updateChildren(nav: child)
                } else {
                    (child as? PublicationViewController)?.didFinishDownloadingEpub(pub: pub)
                }
            }
        }
        
        guard let secondaryNav = viewControllers.last as? UINavigationController else { return }
        
        updateChildren(nav: secondaryNav)
    }
    
    func downloadFailed(pub: Publication){
        let alert = UIAlertController(title: "Download failed",
                                      message: "Downloading \(pub.title) failed. Try again later.",
            preferredStyle: .alert)
        let okBtn = UIAlertAction(title: "OK", style: .cancel)
        alert.addAction(okBtn)
        self.present(alert, animated: true, completion: nil)
        masterVC.downloadFailed(pub: pub)
    }
    
    func downloadProgress(pub: Publication, progress: Float) {
        masterVC.downloadProgress(pub: pub, progress: progress)
        
        var detail = viewControllers.last
        while let detailNav = detail as? UINavigationController {
            detail = detailNav.topViewController
        }
        
        (detail as? PublicationViewController)?.downloadProgress(pub: pub, progress: progress)
    }
    
    // MARK: PublicationActions
    
    func download(pub: Publication) {
        pubsManager.downloadEpub(pub: pub)
        
        masterVC.tableView.reloadData()
        if let detail = (viewControllers.last as? UINavigationController)?.topViewController,
            let pubVC = detail as? PublicationViewController,
            pubVC.pub == pub {
            pubVC.downloadStatus.status = pub.status
        }
    }
    
    func open(pub: Publication) {
        view.addSubview(loadingView)
        //setupActivityIndicatorView()
        
        // switch to async. This ensures that our loading view actually is displayed
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.3) {
            var reader: UIViewController!
            // select the correct type per filetype. Of note - EPubReader must be presented and not pushed
            
            let fileURL = URL(fileURLWithPath: pub.epubPath)
            if let doc = PDFDocument(fileURL: fileURL) {
                let PDFController = PDFViewController.createNew(with: doc, title: pub.title, actionStyle: .activitySheet)
                reader = UINavigationController(rootViewController: PDFController)
            } else {
                // there was an error opening the PDF
                self.loadingView.removeFromSuperview()
                
                // delete the pub as the file is likely currupted. Then ask if the user wants to download it again
                self.pubsManager.deleteEpub(pub)
                print("Error opening \(pub.title) at \(pub.epubPath). File might be currupted")
                let alertDialog = UIAlertController(title: "Error opening pub",
                                                    message: "There was an error opening \(pub.title). The file might be currupt. Re-download?",                                                            preferredStyle: .alert)
                let redownloadClick = UIAlertAction(title: "Yes", style: .default) { _ in
                    self.pubsManager.downloadEpub(forPubWithID: pub.id)
                    if let indexPath = self.masterVC.getVisibleIndex(forPub: pub) {
                        self.masterVC.tableView.reloadRows(at: [indexPath], with: .none)
                    }
                }
                let cancelClick = UIAlertAction(title: "No", style: .cancel)
                alertDialog.addAction(redownloadClick)
                alertDialog.addAction(cancelClick)
                self.present(alertDialog, animated: true)
            }
            
            
            if let reader = reader {
                self.present(reader, animated: true) {
                    self.loadingView.removeFromSuperview()
                }
            }
        }
    }
}
