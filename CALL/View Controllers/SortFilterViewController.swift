//
//  SortFilterTableViewController.swift
//  CALL
//
//  Created by Gregory Niemann on 1/10/17.
//  Copyright © 2017 Greg Niemann. All rights reserved.
//

import UIKit

protocol SortFilterDelegate {
    func updateSortFilterOptions(_ options: SortFilterOptions)
}

class SortFilterViewController: UIViewController {
    var options: SortFilterOptions!
    var sortFilterTableVC: SortFilterTableViewController!
    var delegate: SortFilterDelegate?
    
    init(options: SortFilterOptions) {
        super.init(nibName: nil, bundle: Bundle.main)
        self.options = options
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // instantiate the actual VC
        let storyboard = UIStoryboard(name: "SortFilterStoryboard", bundle: nil)
        sortFilterTableVC = storyboard.instantiateViewController(withIdentifier: "SortFilterVC") as! SortFilterTableViewController
        sortFilterTableVC.options = self.options
        sortFilterTableVC.delegate = delegate
        
        // set up the navigation controller and nav bar
        let nav = UINavigationController(rootViewController: sortFilterTableVC)
        view.addSubview(nav.view)
        addChildViewController(nav)
        nav.didMove(toParentViewController: self)
    }
   
}

class SwitchTableViewCell: UITableViewCell {
    @IBOutlet weak var label: UILabel!
    @IBOutlet weak var switcher: UISwitch!
    
}

class DatePickerTableViewCell: UITableViewCell {
    @IBOutlet weak var datePicker: UIDatePicker!
    
}

class TypePickerTableViewCell: UITableViewCell {
    @IBOutlet weak var typePicker: UIPickerView!
    
}

class SortFilterTableViewController: UITableViewController, UIPickerViewDelegate, UIPickerViewDataSource {
    @IBOutlet weak var doneButton: UIBarButtonItem!
    
    @IBOutlet weak var cancelButton: UIBarButtonItem!
    
    var delegate: SortFilterDelegate?
    
    var sections = ["Sorting Options", "Order to display publication types", "Filter Publications"]
    
    var options: SortFilterOptions!
    var types = PublicationManager.shared.publicationTypes
    
    var cells: [[UITableViewCell]]!
    var visibleCells: [[Bool]]!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // this sets up automatic row heights for the table cells
        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.estimatedRowHeight = 200
        
        // sort section has two rows: ascending/descending and group by
        let dateDirectionCell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell") as! SwitchTableViewCell
        dateDirectionCell.indentationLevel = 2
        dateDirectionCell.label.text = "Show newest publications first"
        dateDirectionCell.switcher.isOn = options.sortDescendingDates
        dateDirectionCell.switcher.addTarget(self, action: #selector(dateDirectionChange(_:)), for: .valueChanged)
        
        let typeSortCell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell") as! SwitchTableViewCell
        typeSortCell.label.text = "Group by publication type"
        typeSortCell.switcher.isOn = options.sortMethod == .byType
        typeSortCell.switcher.addTarget(self, action: #selector(groupByTypeChange(_:)), for: .valueChanged)
        
        let sortRows = [dateDirectionCell, typeSortCell]
        let sortRowsVisible = [true, true]
        
        var groupByRows = [UITableViewCell]()
        var groupByVisible = [Bool]()
        
        let shouldGroupByType = options.sortMethod == .byType
        
        for t in options.typeSortOrder {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = t.type
            cell.indentationLevel = 2
            groupByRows.append(cell)
            groupByVisible.append(shouldGroupByType)
        }
        
        // set up the filter rows
        var filterRowsVisible = [true, false, true, false]
        
        let typeFilterCell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell") as! SwitchTableViewCell
        typeFilterCell.label.text = "Filter by type"
        typeFilterCell.switcher.isOn = options.filterByType
        typeFilterCell.switcher.addTarget(self, action: #selector(typeFilterToggle(_:)), for: .valueChanged)
        
        let typePickerCell = tableView.dequeueReusableCell(withIdentifier: "TypePickerCell") as! TypePickerTableViewCell
        typePickerCell.indentationLevel = 2
        typePickerCell.typePicker.dataSource = self
        typePickerCell.typePicker.delegate = self
        if let setType = options.typeFilter {
            let typeRow = types.index(of: setType)!
            typePickerCell.typePicker.selectRow(typeRow, inComponent: 0, animated: false)
        } else {
            // use the first type as the default
            typePickerCell.typePicker.selectRow(0, inComponent: 0, animated: false)
        }
        filterRowsVisible[1] = options.filterByType
        
        let dateFilterCell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell") as! SwitchTableViewCell
        dateFilterCell.label.text = "Filter by date"
        dateFilterCell.switcher.isOn = options.filterByDate
        dateFilterCell.switcher.addTarget(self, action: #selector(dateFilterToggle(_:)), for: .valueChanged)
        
        let datePickerCell = tableView.dequeueReusableCell(withIdentifier: "DatePickerCell") as! DatePickerTableViewCell
        datePickerCell.datePicker.addTarget(self, action: #selector(changeDatePicker(_:)), for: .valueChanged)
        if let setDate = options.filterDate {
            datePickerCell.datePicker.date = setDate
        }
        
        filterRowsVisible[3] = options.filterByDate

        let filterRows = [typeFilterCell, typePickerCell, dateFilterCell, datePickerCell]
        
        cells = [sortRows, groupByRows, filterRows]
        visibleCells = [sortRowsVisible, groupByVisible, filterRowsVisible]
        
        // set up the tags
        for section in cells {
            for (idx, cell) in section.enumerated() {
                cell.tag = idx
            }
        }
        
        setGroupByVisible()
        tableView.setEditing(options.sortMethod == .byType, animated: false)
        
        self.parent?.preferredContentSize = CGSize(width: 400, height: 1600)
    }
    
    func setGroupByVisible() {
        let groupByVisible = options.sortMethod == .byType
        
        for idx in 0..<cells[1].count {
            visibleCells[1][idx] = groupByVisible
        }
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 1 {
            if options.sortMethod == .byType {
                return sections[1]
            } else {
                return ""
            }
        } else {
            return sections[section]
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        var visRows = 0
        for visibleStatus in visibleCells[section] {
            if visibleStatus {
                visRows += 1
            }
        }
        return visRows
    }

    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = getVisibleCell(at: indexPath) else {
            return UITableViewCell()
        }
        return cell
    }
    
    func getVisibleCell(at indexPath: IndexPath) -> UITableViewCell? {
        var visRows = -1
        for (idx, status) in visibleCells[indexPath.section].enumerated() {
            if status {
                visRows += 1
                if visRows == indexPath.row {
                    return cells[indexPath.section][idx]
                }
            }
        }
        return nil
    }
    
    // Only allow movement of the pub type rows
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section == 1
    }
    
    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath,
                            to destinationIndexPath: IndexPath) {
        if sourceIndexPath == destinationIndexPath {
            return
        }
        let movedPublication = options.typeSortOrder[sourceIndexPath.row]
        if destinationIndexPath.row > sourceIndexPath.row {
            for i in sourceIndexPath.row..<destinationIndexPath.row {
                options.typeSortOrder[i] = options.typeSortOrder[i + 1]
            }
        } else {
            for i in (destinationIndexPath.row + 1...sourceIndexPath.row).reversed() {
                options.typeSortOrder[i] = options.typeSortOrder[i - 1]
            }
        }
        options.typeSortOrder[destinationIndexPath.row] = movedPublication
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section == 1
    }
    
    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {
        return .none
    }
    
    
    func groupByTypeChange(_ sender: UISwitch) {
        if sender.isOn {
            options.sortMethod = .byType
        } else {
            options.sortMethod = .byDate
        }
        tableView.setEditing(sender.isOn, animated: false)
        setGroupByVisible()
        tableView.reloadData()
    }

    func dateDirectionChange(_ sender: UISwitch) {
        options.sortDescendingDates = sender.isOn
    }
    
    func typeFilterToggle(_ sender: UISwitch) {
        // switch the filterByType option and show or hide the cell
        options.filterByType = sender.isOn
        visibleCells[2][1] = sender.isOn
        
        if sender.isOn {
            options.typeFilter = types[(cells[2][1] as! TypePickerTableViewCell).typePicker.selectedRow(inComponent: 0)]
        } else {
            options.typeFilter = nil
        }
        tableView.reloadData()
    }
    
    func dateFilterToggle(_ sender: UISwitch) {
        // switch the filterByDate option and show/hide the cell
        options.filterByDate = sender.isOn
        visibleCells[2][3] = sender.isOn
        if sender.isOn {
            options.filterDate = (cells[2][3] as! DatePickerTableViewCell).datePicker.date
        } else {
            options.filterDate = nil
        }
        tableView.reloadData()
    }
    
    func changeDatePicker(_ sender: UIDatePicker) {
        options.filterDate = sender.date
    }
    
    
    @IBAction func finished(_ sender: UIBarButtonItem) {
        if sender == doneButton {
            delegate?.updateSortFilterOptions(options)
        }
        dismiss(animated: true, completion: nil)
    }
    
    // MARK: UITypePickerView delegate and data source
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return types.count
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return types[row].type
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        options.typeFilter = types[row]
    }

}






