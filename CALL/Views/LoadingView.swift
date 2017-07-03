//
//  LoadingView.swift
//  CALL
//
//  Created by Gregory Niemann on 6/9/17.
//  Copyright © 2017 Greg Niemann. All rights reserved.
//

/*
 LoadingView - shows an ActivityIndicator and 'Loading...' message
 
 Create by calling init with the VC's view (or other central view)
 
 To show and start, add as a subview
 
 To hide, remove from superview
 */

import UIKit

class LoadingView: UIView {
    let activitySpinner = UIActivityIndicatorView(activityIndicatorStyle: .white)
    let loadingLabel = UILabel(frame: CGRect(x: 55, y: 0, width: 95, height: 50))
    
    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 150, height: 50))
        center = CGPoint(x: UIScreen.main.bounds.size.width/2, y: UIScreen.main.bounds.size.height/2)
        layer.cornerRadius = 15
        backgroundColor = UIColor(white: 0, alpha: 0.7)
        
        loadingLabel.text = "Loading..."
        loadingLabel.textColor = UIColor.white
        loadingLabel.font = UIFont.systemFont(ofSize: 18, weight: UIFontWeightSemibold)
        
        activitySpinner.hidesWhenStopped = false
        activitySpinner.frame = CGRect(x: 5, y: 0, width: 50, height: 50)
        
        addSubview(loadingLabel)
        addSubview(activitySpinner)
        
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)
        if newSuperview != nil {
            activitySpinner.startAnimating()
        } else {
            activitySpinner.stopAnimating()
        }
    }
    
}
