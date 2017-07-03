//
//  DownloadStatusView.swift
//  CALL
//
//  Created by Gregory Niemann on 6/8/17.
//  Copyright © 2017 Greg Niemann. All rights reserved.
//

import UIKit

protocol DownloadStatusViewDelegate {
    func openTouched(sender: DownloadStatusView)
    func downloadTouched(sender: DownloadStatusView)
}

@IBDesignable class DownloadStatusView: UIView {

    @IBOutlet weak var downloadProgressView: UIView!
    @IBOutlet weak var downloadProgressBar: UIProgressView!
    @IBOutlet weak var downloadOpenButton: UIButton!

    // MARK: Properties
    var view: UIView!
    var status: Publication.PubStatus = .NotDownloaded {
        didSet {
            downloadProgressView.isHidden = (status != .Downloading)
            downloadOpenButton.isHidden = (status == .Downloading)
            
            switch status {
            case .IsDownloaded:
                downloadOpenButton.setTitle("Open", for: .normal)
            case .NotDownloaded:
                downloadOpenButton.setTitle("Download", for: .normal)
            default:
                break
            }
        }
    }
    var delegate: DownloadStatusViewDelegate?
    
    func loadFromXib() -> UIView {
        let bundle = Bundle(for: type(of: self))
        let nib = UINib(nibName: String(describing: type(of: self)) , bundle: bundle)
        return nib.instantiate(withOwner: self, options: nil).first as! UIView
    }
    
    func setup() {
        view = loadFromXib()
        view.frame = bounds
        view.autoresizingMask = [
            UIViewAutoresizing.flexibleWidth,
            UIViewAutoresizing.flexibleHeight
        ]
        addSubview(view)
        
        downloadOpenButton.layer.borderColor = UIColor.blue.cgColor
        downloadOpenButton.layer.borderWidth = 1
        downloadOpenButton.layer.cornerRadius = 5
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    func setProgress(progress: Float) {
        downloadProgressBar.progress = progress
    }
    
    @IBAction func buttonTapped(_ sender: UIButton) {
        if status == .IsDownloaded {
            delegate?.openTouched(sender: self)
        } else if status == .NotDownloaded {
            delegate?.downloadTouched(sender: self)
        }
    }
    
    
}
