//
//  SettingsViewController.swift
//  CALL
//
//  Created by Gregory Niemann on 1/6/17.
//  Copyright © 2017 Greg Niemann. All rights reserved.
//

import UIKit
import MessageUI

/*
 The SettingsTableViewController shows the app settings
 It has two sections - notifications and auto downloads. Both are filled with the publication types
 
 The footer is the website and feeedback links
*/
class SettingsViewController: UITableViewController, MFMailComposeViewControllerDelegate{
    
    var sectionTitles: [String] = ["Receive notifications for...", "Auto download new..."]
    var settingsKeys: [String] = ["notifications", "downloads"]
    var settings = [[String: Bool]]()
    var defaults: UserDefaults!
    
    static func makeInNavController() -> UINavigationController {
        let settingsVC = SettingsViewController()
        let settingsNav = UINavigationController(rootViewController: settingsVC)
        return settingsNav
    }
    
    init() {
        super.init(nibName: nil, bundle: Bundle.main)
        
        defaults = UserDefaults.standard
        
        for section in settingsKeys {
            settings.append(defaults.dictionary(forKey: section) as! [String : Bool])
        }
        let height = (settingsKeys.count + 3) * 100 + 64
        preferredContentSize = CGSize(width: 400, height: height)

    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "settingsCell")
    
        tableView.separatorStyle = .none
        navigationItem.title = "Settings"
        let doneBtn = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(donePress(_:)))
        navigationItem.rightBarButtonItem = doneBtn
        
        // add the buttons to the table's footer
        let footer = UIView(frame: CGRect(x: 0, y: 0, width: tableView.frame.size.width, height: 70))

        let sendFeedback = UIButton()
        sendFeedback.setTitle("Send Feedback to CALL", for: .normal)
        sendFeedback.setTitleColor(UIColor.blue, for: .normal)
        sendFeedback.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: UIFontWeightBold)
        sendFeedback.addTarget(self, action: #selector(sendFeedback(_:)), for: .touchDown)
        sendFeedback.translatesAutoresizingMaskIntoConstraints = false
        
        let gotoWebsite = UIButton()
        gotoWebsite.setTitle("Visit CALL's Website", for: .normal)
        gotoWebsite.setTitleColor(UIColor.blue, for: .normal)
        gotoWebsite.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: UIFontWeightBold)
        gotoWebsite.addTarget(self, action: #selector(visitWebsite(_:)), for: .touchDown)
        gotoWebsite.translatesAutoresizingMaskIntoConstraints = false
        
        footer.addSubview(sendFeedback)
        footer.addSubview(gotoWebsite)
        tableView.tableFooterView = footer
        
        // set contraints to put the feedback and website buttons centered at the bottom of the view
        NSLayoutConstraint.activate([sendFeedback.topAnchor.constraint(equalTo: footer.topAnchor, constant: 10),
                                     sendFeedback.centerXAnchor.constraint(equalTo: footer.centerXAnchor) ,
                                     sendFeedback.heightAnchor.constraint(equalToConstant: 20),
                                     gotoWebsite.topAnchor.constraint(equalTo: sendFeedback.bottomAnchor, constant: 10),
                                     gotoWebsite.centerXAnchor.constraint(equalTo: footer.centerXAnchor),
                                     gotoWebsite.heightAnchor.constraint(equalToConstant: 20)])
        
        
        
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return sectionTitles.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return settings[section].count
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sectionTitles[section]
    }

    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "settingsCell", for: indexPath)

        let key = getKeyFromIndexPath(indexPath)
        
        cell.textLabel!.text = key
        
        if settings[indexPath.section][key]! {
            cell.accessoryType = .checkmark
        } else {
            cell.accessoryType = .none
        }

        return cell
    }
    
    func getKeyFromIndexPath(_ indexPath: IndexPath) -> String {
        let labels = [String](settings[indexPath.section].keys).sorted()
        let key = labels[indexPath.row]
        
        return key
    }
    

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let key = getKeyFromIndexPath(indexPath)
        
        settings[indexPath.section][key] = !settings[indexPath.section][key]!
        
        tableView.reloadRows(at: [indexPath], with: .none)
    }
    
    // MARK: Actions
    
    func donePress(_ sender: UIBarButtonItem) {
        for (idx, settingKey) in settingsKeys.enumerated() {
            defaults.set(settings[idx], forKey: settingKey)
        }
        
        dismiss(animated: true, completion: nil)
    }
    
    // Opens a new email message to be sent to the feedback email
    func sendFeedback(_ sender: UIButton) {
        if MFMailComposeViewController.canSendMail() {
            let mailer = MFMailComposeViewController()
            mailer.mailComposeDelegate = self
            mailer.setSubject("App Feedback")
            mailer.setToRecipients(["usarmy.leavenworth.mccoe.mbx.call-webteam@mail.mil"])
            
            if self.traitCollection.userInterfaceIdiom == .pad {
                mailer.modalPresentationStyle = .formSheet
            }
            present(mailer, animated: true, completion: nil)
        }
        
        
    }
    
    // opens the website in Safari
    func visitWebsite(_ sender: UIButton) {
        UIApplication.shared.openURL(URL(string: "http://call.army.mil")!)
    }
    
    // MARK: MFMailComposeViewControllerDelegate
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult,
                               error: Error?) {
        self.dismiss(animated: true, completion: nil)
    }
}
