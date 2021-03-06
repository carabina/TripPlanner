//
//  AutoCompleteTextField.swift
//  TripPlanner
//
//  Created by James Pereira on 2018/11/03.
//  Copyright © 2018 Code Challenge. All rights reserved.
//

import Foundation
import UIKit

// MARK: - AutoCompleteTextFieldDelegate

public protocol AutoCompleteTextFieldDelegate: class {
    /// Called when auto-complete results are updated.
    /// - parameter textField: The `AutoCompleteTextField` filtering the results.
    /// - parameter results: A list of `AutoCompletable` results, or `nil` if the text field has no text in it.
    func autoCompleteTextField(_ textField: AutoCompleteTextField, didFilter results: [AutoCompletable]?)
    
    /// Called before a result is about to be selected.
    /// - parameter textField: The `AutoCompleteTextField` the result is selected from.
    /// - parameter result: The `AutoCompletable` result that is about to be selected.
    /// - returns: `true` if the result should be selected, or `false` if it should not.
    func autoCompleteTextField(_ textField: AutoCompleteTextField, shouldSelect result: AutoCompletable) -> Bool
    
    /// Called after a result is selected.
    /// - parameter textField: The `AutoCompleteTextField` the result is selected from.
    /// - parameter result: The `AutoCompletable` result that was just selected.
    func autoCompleteTextField(_ textField: AutoCompleteTextField, didSelect result: AutoCompletable)
}

// MARK: - AutoCompleteTextFieldDelegate Default Implementation
public extension AutoCompleteTextFieldDelegate {
    func autoCompleteTextField(_ textField: AutoCompleteTextField, didFilter results: [AutoCompletable]?) {
        
    }
    func autoCompleteTextField(_ textField: AutoCompleteTextField, shouldSelect result: AutoCompletable) -> Bool {
        return true
    }
    func autoCompleteTextField(_ textField: AutoCompleteTextField, didSelect result: AutoCompletable) {
        
    }
}

// MARK: - AutoCompleteTextField

open class AutoCompleteTextField: UITextField, UITextFieldDelegate, UITableViewDelegate, UITableViewDataSource {
    
    // MARK: - Public Enums
    
    /// The direction that the result list will flow.
    public enum ResultListDirection {
        case down
        case up
    }
    
    // MARK: - Public Properties
    
    /// The delegate for auto-complete methods.
    open weak var autocompleteDelegate: AutoCompleteTextFieldDelegate?
    
    /// The list of objects to use in auto-completion.
    open var dataSource: [AutoCompletable] = [] {
        didSet {
            guard shouldBuildTrieOnNewDataSource else { return }
            createAutoCompleteTrie()
        }
    }
    
    /// If `true`, text field will look for auto-complete results.
    open var shouldAutoComplete: Bool = true
    
    /// If `true`, a search trie will be built when a new `dataSource` is set.
    open var shouldBuildTrieOnNewDataSource: Bool = true
    
    /// If `true`, shows a drop down list of strings for auto-completion.
    open var shouldShowResultList: Bool = true
    
    /// If `true`, shows the rest of an auto-completion result inline with the input text.
    open var shouldShowInlineAutoCompletion: Bool = false
    
    /// If `true`, the auto-complete filtering will be case sensitive.
    open var isCaseSensitive: Bool = false
    
    /// The maximum number of auto-complete results shown in the result list. If `nil`, there is no limit.
    open var maxResultCount: Int? = 50
    
    /// The maximum height of the result list.
    open var maxResultListHeight: CGFloat = 150
    
    /// The x-offset of the result list.
    open var resultListOffsetX: CGFloat = 0 {
        didSet {
            resultListTableViewLeadingConstraint?.constant = resultListOffsetX
            resultListTableViewTrailingConstraint?.constant = resultListOffsetX
            layoutIfNeeded()
        }
    }
    
    /// The y-offset of the result list.
    open var resultListOffsetY: CGFloat = 0 {
        didSet {
            resultListTableViewAnchorConstraint?.constant = resultListDirection == .down ? resultListOffsetY : -resultListOffsetY
            layoutIfNeeded()
        }
    }
    
    /// The color of the text of the auto-complete results.
    open var resultListTextColor: UIColor? = .black
    
    /// The background color of the result list.
    open var resultListBackgroundColor: UIColor? {
        get { return resultListTableView.backgroundColor }
        set { resultListTableView.backgroundColor = newValue }
    }
    
    /// The layer for the result list.
    open var resultListLayer: CALayer {
        return resultListTableView.layer
    }
    
    /// The content insets of the result list.
    open var resultListContentInset: UIEdgeInsets {
        get { return resultListTableView.contentInset }
        set { resultListTableView.contentInset = newValue }
    }
    
    /// The separator style for cells in the result list.
    open var resultListSeparatorStyle: UITableViewCell.SeparatorStyle {
        get { return resultListTableView.separatorStyle }
        set { resultListTableView.separatorStyle = newValue }
    }
    
    /// The separator inset for cells in the result list.
    open var resultListSeparatorInset: UIEdgeInsets {
        get { return resultListTableView.separatorInset }
        set { resultListTableView.separatorInset = newValue }
    }
    
    /// The height of the rows in the result list.
    open var resultListRowHeight: CGFloat = 0
    
    /// The font for the text in the result list.
    open var resultListFont: UIFont? = UIFont.systemFont(ofSize: 14)
    
    /// String attributes for the text in a result that matches the text in the text field.
    open var matchedTextAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.boldSystemFont(ofSize: 14)
    ]
    
    /// String attributes for the rest of an auto-completion result inline with the input text.
    open var inlineAutoCompletionTextAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: UIColor.lightGray, .backgroundColor: UIColor.clear
    ]
    
    /// The direction the result list will flow.
    open var resultListDirection: ResultListDirection = .down {
        didSet {
            resultListTableViewAnchorConstraint?.isActive = false
            resultListTableViewAnchorConstraint = NSLayoutConstraint(
                item: resultListTableView, attribute: resultListDirection == .down ? .top : .bottom,
                relatedBy: .equal,
                toItem: self, attribute: resultListDirection == .down ? .bottom : .top,
                multiplier: 1, constant: resultListDirection == .down ? resultListOffsetY : -resultListOffsetY
            )
            resultListTableViewAnchorConstraint?.isActive = true
            layoutIfNeeded()
        }
    }
    
    // MARK: - Private Properties
    
    private var loadingView: UIView
    private var loadingActivityIndicatorView: UIActivityIndicatorView
    private var previousRightView: UIView?
    private var previousRightViewMode: UITextField.ViewMode = .never
    
    private var resultListTableView: UITableView
    private var resultListTableViewLeadingConstraint: NSLayoutConstraint?
    private var resultListTableViewTrailingConstraint: NSLayoutConstraint?
    private var resultListTableViewAnchorConstraint: NSLayoutConstraint?
    private var resultListTableViewHeightConstraint: NSLayoutConstraint?
    
    private weak var textFieldDelegate: UITextFieldDelegate?
    
    private var autoCompleteTree: AutoCompleteTree?
    private var filteredResults: [AutoCompletable] = []
    
    private var currentResultListHeight: CGFloat {
        let totalHeight = frame.height * CGFloat(filteredResults.count)
        return totalHeight < maxResultListHeight ? totalHeight : maxResultListHeight
    }
    
    private var currentInputText: String = ""
    private var currentInlineAutoCompletionText: String = ""
    private var autoCompletionResultIndex: Int = 0
    
    private var isFilteringResults: Bool = false
    private var isTextFieldUIUpdating: Bool = false
    
    private var loadTrieWorkItem: DispatchWorkItem?
    private var filterDataSourceWorkItem: DispatchWorkItem?
    
    // MARK: - Override Properties
    
    open override var delegate: UITextFieldDelegate? {
        didSet {
            if delegate === self { return }
            textFieldDelegate = delegate
            delegate = oldValue
        }
    }
    
    open override var selectedTextRange: UITextRange? {
        didSet {
            guard
                let text = text, let selectedRange = selectedTextRange,
                offset(from: beginningOfDocument, to: selectedRange.start) > text.count - currentInlineAutoCompletionText.count,
                let lastPosition = position(from: beginningOfDocument, offset: text.count - currentInlineAutoCompletionText.count)
                else { return }
            selectedTextRange = textRange(from: lastPosition, to: lastPosition)
        }
    }
    
    // MARK: - initialzers
    
    public override init(frame: CGRect) {
        loadingView = UIView()
        loadingActivityIndicatorView = UIActivityIndicatorView(style: .gray)
        resultListTableView = UITableView()
        super.init(frame: frame)
        setupAutoCompleteTextField()
        formatResultListTableView()//new
    }
    
    public required init?(coder aDecoder: NSCoder) {
        loadingView = UIView()
        loadingActivityIndicatorView = UIActivityIndicatorView(style: .gray)
        resultListTableView = UITableView()
        super.init(coder: aDecoder)
        setupAutoCompleteTextField()
        formatResultListTableView()//new
    }
    
    // MARK: - Lifecycle
    
    open override func awakeFromNib() {
        super.awakeFromNib()
        formatResultListTableView()
    }
    
    // MARK: - Setup Functions
    
    private func setupAutoCompleteTextField() {
        delegate = self
        resultListTableView.delegate = self
        resultListTableView.dataSource = self
        addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)
        createLoadingView()
        createResultListTableView()
    }
    
    private func createLoadingView() {
        loadingView.frame = CGRect(x: 0, y: 0, width: frame.height, height: frame.height)
        loadingView.addSubview(loadingActivityIndicatorView)
        loadingActivityIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        loadingActivityIndicatorView.isHidden = false
        NSLayoutConstraint(
            item: loadingActivityIndicatorView, attribute: .centerX,
            relatedBy: .equal,
            toItem: loadingView, attribute: .centerX,
            multiplier: 1, constant: 0
            ).isActive = true
        NSLayoutConstraint(
            item: loadingActivityIndicatorView, attribute: .centerY,
            relatedBy: .equal,
            toItem: loadingView, attribute: .centerY,
            multiplier: 1, constant: 0
            ).isActive = true
    }
    
    private func createResultListTableView() {
        addSubview(resultListTableView)
        sendSubviewToBack(resultListTableView)
        resultListTableView.translatesAutoresizingMaskIntoConstraints = false
        resultListTableViewLeadingConstraint = NSLayoutConstraint(
            item: resultListTableView, attribute: .leading,
            relatedBy: .equal,
            toItem: self, attribute: .leading,
            multiplier: 1, constant: resultListOffsetX
        )
        resultListTableViewLeadingConstraint?.isActive = true
        resultListTableViewTrailingConstraint = NSLayoutConstraint(
            item: resultListTableView, attribute: .trailing,
            relatedBy: .equal,
            toItem: self, attribute: .trailing,
            multiplier: 1, constant: resultListOffsetX
        )
        resultListTableViewTrailingConstraint?.isActive = true
        resultListTableViewAnchorConstraint = NSLayoutConstraint(
            item: resultListTableView, attribute: .top,
            relatedBy: .equal,
            toItem: self, attribute: .bottom,
            multiplier: 1, constant: resultListOffsetY
        )
        resultListTableViewAnchorConstraint?.isActive = true
        resultListTableViewHeightConstraint = NSLayoutConstraint(
            item: resultListTableView, attribute: .height,
            relatedBy: .equal,
            toItem: nil, attribute: .notAnAttribute,
            multiplier: 1, constant: 0
        )
        resultListTableViewHeightConstraint?.isActive = true
    }
    
    private func formatResultListTableView() {
        if borderStyle == .roundedRect {
            resultListTableView.layer.borderColor = UIColor.lightGray.cgColor
            resultListTableView.layer.borderWidth = 0.25
            resultListTableView.layer.cornerRadius = 5
            resultListTableView.separatorStyle = .singleLine
            resultListOffsetY = -15
            resultListContentInset.top = 15
        } else if borderStyle == .line || borderStyle == .bezel {
            resultListTableView.layer.borderColor = UIColor.black.cgColor
            resultListTableView.layer.borderWidth = 0.5
            resultListTableView.separatorStyle = .singleLine
            resultListOffsetY = -1
            resultListContentInset.top = 1
        } else {
            resultListTableView.separatorStyle = .none
            resultListOffsetY = 0
        }
        
        resultListRowHeight = frame.height
        resultListTableView.separatorInset = .zero
        
        resultListBackgroundColor = backgroundColor
        resultListFont = font
        if let font = font {
            matchedTextAttributes = [.font: UIFont(name: "\(font.fontName)-Bold", size: font.pointSize) ?? UIFont.systemFont(ofSize: 14, weight: .bold)]
        }
        
        resultListTableView.isHidden = true
        resultListTableView.reloadData()
    }
    
    // MARK: - Public Functions
    
    /// Sets the current text in the text field, to the result at `index`.
    /// - parameter index: The index of the auto-complete result to select.
    open func selectResult(at index: Int) {
        guard index >= 0, index < filteredResults.count else { return }
        let result = filteredResults[index]
        if autocompleteDelegate?.autoCompleteTextField(self, shouldSelect: result) ?? true {
            currentInputText = result.autocompleteString
            currentInlineAutoCompletionText = ""
            text = result.autocompleteString
            playHideResultListAnimation()
            autocompleteDelegate?.autoCompleteTextField(self, didSelect: result)
        }
    }
    
    /// Sets the current text in the text field to the first result in the list.
    open func selectFirstResult() {
        selectResult(at: 0)
    }
    
    /// Sets the current result to be shown in inline auto-completion.
    /// - parameter index: The index of the auto-complete result to set to appear inline.
    open func setResultForInlineAutoCompletion(at index: Int) {
        autoCompletionResultIndex = index
        if shouldShowInlineAutoCompletion {
            showInlineAutoCompletion(for: currentInputText, at: autoCompletionResultIndex)
        }
    }
    
    /// Loads an `ACTrie` into the `AutoCompleteTextField`.
    /// - parameter ACTrie: The trie to load.
    open func load(autoCompleteTrie: AutoCompleteTrie) {
        loadTrieWorkItem?.cancel()
        loadTrieWorkItem = nil
        self.autoCompleteTree = autoCompleteTrie
    }
    
    /// Loads an `AutoCompleteDataSource` into the `AutoCompleteTextField`.
    /// - parameter dataSource: The data source to load.
    open func load(dataSource: AutoCompleteDataSource) {
        self.dataSource = dataSource.data
        if let autoCompleteTrie = dataSource.autoCompleteTree {
            loadTrieWorkItem?.cancel()
            loadTrieWorkItem = nil
            self.autoCompleteTree = autoCompleteTrie
        }
    }
    

    /// Override this function to use a custom cell in the result list.
    /// - parameter indexPath: The index path of the new cell.
    open func setupResultListTableViewCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: "ACTableViewCell")
        cell.backgroundColor = .clear
        cell.textLabel?.textColor = resultListTextColor
        cell.textLabel?.font = resultListFont
        cell.textLabel?.attributedText = textByApplying(
            attributes: matchedTextAttributes,
            to: filteredResults[indexPath.row].autocompleteString,
            before: currentInputText.count
        )
        cell.selectionStyle = .none
        return cell
    }
    
    // MARK: - Private Logic Functions
    
    private func createAutoCompleteTrie() {
        loadTrieWorkItem?.cancel()
        loadTrieWorkItem = DispatchWorkItem { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.autoCompleteTree = AutoCompleteTrie(dataSource: strongSelf.dataSource, isCaseSensitive: strongSelf.isCaseSensitive)
            print("Preloaded \(strongSelf.dataSource.count) Total Results")
        }
        guard let loadTrieWorkItem = loadTrieWorkItem else { return }
        DispatchQueue.global(qos: .background).async(execute: loadTrieWorkItem)
    }
    
    private func processResults(for updatedText: String) {
        currentInputText = substring(of: updatedText, before: updatedText.count - currentInlineAutoCompletionText.count)
        autoCompletionResultIndex = 0
        isFilteringResults = true
        filterDataSource(with: currentInputText) { [weak self] in
            guard let strongSelf = self else { return }
            if strongSelf.shouldShowInlineAutoCompletion, !strongSelf.isTextFieldUIUpdating {
                strongSelf.showInlineAutoCompletion(for: strongSelf.currentInputText, at: strongSelf.autoCompletionResultIndex)
            }
            strongSelf.isFilteringResults = false
            strongSelf.hideLoadingIndicator()
            !strongSelf.currentInputText.isEmpty ? strongSelf.playShowResultListAnimation() : strongSelf.playHideResultListAnimation()
        }
    }
    
    private func filterDataSource(with inputText: String, completion: @escaping () -> Void) {
        filterDataSourceWorkItem?.cancel()
        guard !inputText.isEmpty else {
            filterDataSourceWorkItem = nil
            filteredResults = []
            autocompleteDelegate?.autoCompleteTextField(self, didFilter: nil)
            completion()
            return
        }
        filterDataSourceWorkItem = DispatchWorkItem { [weak self] in
            guard let strongSelf = self else { return }
            if let ACTrie = strongSelf.autoCompleteTree {
                strongSelf.filteredResults = ACTrie.results(for: inputText, limit: strongSelf.maxResultCount) ?? strongSelf.dataSource
            } else {
                strongSelf.filteredResults = strongSelf.filterResultsFrom(unsortedData: strongSelf.dataSource, with: inputText)
            }
            DispatchQueue.main.async {
                strongSelf.autocompleteDelegate?.autoCompleteTextField(strongSelf, didFilter: strongSelf.filteredResults)
                completion()
            }
        }
        guard let filterDataSourceWorkItem = filterDataSourceWorkItem else { return }
        DispatchQueue.global(qos: .background).async(execute: filterDataSourceWorkItem)
    }
    
    private func filterResultsFrom(unsortedData: [AutoCompletable], with inputText: String) -> [AutoCompletable] {
        var filteredData = [AutoCompletable]()
        for result in unsortedData {
            guard inputText.count <= result.autocompleteString.count else { continue }
            if isCaseSensitive {
                if result.autocompleteString.hasPrefix(inputText) {
                    filteredData.append(result)
                }
            } else {
                if result.autocompleteString.lowercased().hasPrefix(inputText.lowercased()) {
                    filteredData.append(result)
                }
            }
        }
        let sortedData = filteredData.sorted { $0.autocompleteString.count < $1.autocompleteString.count }
        if let maxResultCount = maxResultCount {
            return [AutoCompletable](sortedData.prefix(maxResultCount))
        }
        return sortedData
    }
    
    private func showInlineAutoCompletion(for inputText: String, at index: Int) {
        guard let cursorPosition = position(from: beginningOfDocument, offset: inputText.count) else { return }
        var textCompletion = ""
        if !inputText.isEmpty, index >= 0, index < filteredResults.count {
            textCompletion = substring(of: filteredResults[index].autocompleteString, after: inputText.count)
        }
        currentInlineAutoCompletionText = textCompletion
        attributedText = textByApplying(
            attributes: inlineAutoCompletionTextAttributes,
            to: inputText + textCompletion,
            after: inputText.count
        )
        selectedTextRange = textRange(from: cursorPosition, to: cursorPosition)
    }
    
    // MARK: - Utility Functions
    
    private func substring(of string: String, before index: Int) -> String {
        guard index > -1, index <= string.count else { return "" }
        return String(string[string.startIndex..<string.index(string.startIndex, offsetBy: index)])
    }
    
    private func substring(of string: String, after index: Int) -> String {
        guard index >= -1, index < string.count else { return "" }
        return String(string[string.index(string.startIndex, offsetBy: index)..<string.endIndex])
    }
    
    private func textByApplying(attributes: [NSAttributedString.Key: Any], to text: String, before index: Int) -> NSAttributedString {
        guard index > -1, index <= text.count else { return NSAttributedString(string: text) }
        let attributedEndIndex = text.index(text.startIndex, offsetBy: index)
        let attributedString = NSMutableAttributedString(string: String(text[text.startIndex..<attributedEndIndex]), attributes: attributes)
        attributedString.append(NSAttributedString(string: String(text[attributedEndIndex..<text.endIndex])))
        return attributedString
    }
    
    private func textByApplying(attributes: [NSAttributedString.Key: Any], to text: String, after index: Int) -> NSAttributedString {
        guard index >= -1, index < text.count else { return NSAttributedString(string: text) }
        let attributedStartIndex = text.index(text.startIndex, offsetBy: index)
        let attributedString = NSMutableAttributedString(string: String(text[text.startIndex..<attributedStartIndex]))
        attributedString.append(NSAttributedString(string: String(text[attributedStartIndex..<text.endIndex]), attributes: attributes))
        return attributedString
    }
    
    private func showOnlyInputText() {
        currentInlineAutoCompletionText = ""
        text = currentInputText
    }
    
    private func resetAutoCompleteTextField() {
        filteredResults = []
        currentInlineAutoCompletionText = ""
        currentInputText = ""
        text = currentInputText
    }
    
    // MARK: - Override Functions
    
    open override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for subview in subviews {
            let view = subview.hitTest(convert(point, to: subview), with: event)
            if let view = view { return view }
        }
        return super.hitTest(point, with: event)
    }
    
    // MARK: - UITableViewDelegate
    
    open func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredResults.count
    }
    
    open func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return resultListRowHeight
    }
    
    open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let backupCell = UITableViewCell(style: .default, reuseIdentifier: "BackupTableViewCell")
        backupCell.backgroundColor = .clear
        guard !isFilteringResults, indexPath.row >= 0, indexPath.row < filteredResults.count else { return backupCell }
        return setupResultListTableViewCell(at: indexPath)
    }
    
    open func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectResult(at: indexPath.row)
    }
    
    // MARK: - UITextFieldDelegate
    
    open func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        isTextFieldUIUpdating = true
        if shouldAutoComplete, let nsText = textField.text as NSString? {
            let updatedText = nsText.replacingCharacters(in: range, with: string)
            processResults(for: updatedText)
        }
        return textFieldDelegate?.textField?(textField, shouldChangeCharactersIn: range, replacementString: string) ?? true
    }
    
    @objc private func textFieldDidChange(_ textField: UITextField) {
        if shouldAutoComplete {
            if isFilteringResults {
                // debounce
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let strongSelf = self, strongSelf.isFilteringResults else { return }
                    strongSelf.showLoadingIndicator()
                }
                if shouldShowInlineAutoCompletion {
                    showOnlyInputText()
                }
            } else {
                if shouldShowInlineAutoCompletion {
                    showInlineAutoCompletion(for: currentInputText, at: autoCompletionResultIndex)
                }
            }
        }
        isTextFieldUIUpdating = false
    }
    
    open func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if (textField.text?.isEmpty)! {
            // FIXME: autoCompleteTrie has a check for this hard coded value
            // FIXME: This was done just to get the dropdown resultlist displayed
            filterDataSource(with: "*") { [weak self] in
                guard let strongSelf = self else { return }
                if strongSelf.shouldShowInlineAutoCompletion, !strongSelf.isTextFieldUIUpdating {
                    strongSelf.showInlineAutoCompletion(for: strongSelf.currentInputText, at: strongSelf.autoCompletionResultIndex)
                }
                strongSelf.isFilteringResults = false
                strongSelf.hideLoadingIndicator()
                strongSelf.playShowResultListAnimation()
                //!strongSelf.currentInputText.isEmpty ? strongSelf.playShowResultListAnimation() : strongSelf.playHideResultListAnimation()
            }
        }
        return textFieldDelegate?.textFieldShouldReturn?(textField) ?? true
    }
    
    open func textFieldShouldClear(_ textField: UITextField) -> Bool {
        resetAutoCompleteTextField()
        playHideResultListAnimation()
        return textFieldDelegate?.textFieldShouldClear?(textField) ?? true
    }
    
    open func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        return textFieldDelegate?.textFieldShouldBeginEditing?(textField) ?? true
    }
    
    open func textFieldDidBeginEditing(_ textField: UITextField) {
        if let text = textField.text, !text.isEmpty {
            currentInputText = text
            autoCompletionResultIndex = 0
            isFilteringResults = true
            filterDataSource(with: text) { [weak self] in
                guard let strongSelf = self else { return }
                if strongSelf.shouldShowInlineAutoCompletion {
                    strongSelf.showInlineAutoCompletion(for: strongSelf.currentInputText, at: strongSelf.autoCompletionResultIndex)
                }
                strongSelf.isFilteringResults = false
                strongSelf.hideLoadingIndicator()
                strongSelf.playShowResultListAnimation()
            }
        }
        textFieldDelegate?.textFieldDidBeginEditing?(textField)
    }
    
    open func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        return textFieldDelegate?.textFieldShouldEndEditing?(textField) ?? true
    }
    
    open func textFieldDidEndEditing(_ textField: UITextField) {
        showOnlyInputText()
        playHideResultListAnimation()
        textFieldDelegate?.textFieldDidEndEditing?(textField)
    }
    
    open func textFieldDidEndEditing(_ textField: UITextField, reason: UITextField.DidEndEditingReason) {
        showOnlyInputText()
        playHideResultListAnimation()
        textFieldDelegate?.textFieldDidEndEditing?(textField, reason: reason)
    }
    
    // MARK: - Animations
    
    private func playShowResultListAnimation() {
        guard shouldShowResultList else { return }
        resultListTableView.reloadData()
        resultListTableView.isHidden = false
        layoutIfNeeded()
        UIView.animate(withDuration: 0.25, delay: 0.0, options: [.curveEaseOut], animations: {
            self.resultListTableViewHeightConstraint?.constant = self.currentResultListHeight
            self.layoutIfNeeded()
        }, completion: nil)
    }
    
    private func playHideResultListAnimation() {
        guard shouldShowResultList else { return }
        layoutIfNeeded()
        UIView.animate(withDuration: 0.25, delay: 0.0, options: [.curveEaseOut], animations: {
            self.resultListTableViewHeightConstraint?.constant = 0.0
            self.layoutIfNeeded()
        }, completion: { _ in
            self.resultListTableView.isHidden = true
        })
    }
    
    private func showLoadingIndicator() {
        previousRightView = rightView
        previousRightViewMode = rightViewMode
        rightView = loadingView
        rightViewMode = .always
        loadingActivityIndicatorView.startAnimating()
    }
    
    private func hideLoadingIndicator() {
        rightView = previousRightView
        rightViewMode = previousRightViewMode
        loadingActivityIndicatorView.stopAnimating()
    }
}
