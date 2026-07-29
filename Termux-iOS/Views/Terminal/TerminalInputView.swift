//
//  TerminalInputView.swift
//  Termux-iOS
//
//  UIKit Keyboard Bridge (UIKeyInput) for interactive terminal typing.
//  Ensures normal on-screen keyboard, backspace, enter, and ASCII typing work seamlessly.
//

import SwiftUI
import UIKit

public class TerminalKeyInputView: UIView, UIKeyInput, UITextInputTraits {
    public weak var session: TerminalSession?
    
    // UITextInputTraits for terminal-friendly typing
    public var autocorrectionType: UITextAutocorrectionType = .no
    public var autocapitalizationType: UITextAutocapitalizationType = .none
    public var spellCheckingType: UITextSpellCheckingType = .no
    public var smartQuotesType: UITextSmartQuotesType = .no
    public var smartDashesType: UITextSmartDashesType = .no
    public var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    public var keyboardType: UIKeyboardType = .asciiCapable
    public var returnKeyType: UIReturnKeyType = .default
    public var keyboardAppearance: UIKeyboardAppearance = .dark
    
    public override var canBecomeFirstResponder: Bool {
        return true
    }
    
    public var hasText: Bool {
        return true
    }
    
    public init(session: TerminalSession) {
        self.session = session
        super.init(frame: .zero)
        self.isUserInteractionEnabled = true
        self.backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func insertText(_ text: String) {
        guard let session = session else { return }
        if text == "\n" || text == "\r" {
            session.handleInputString("\r")
        } else {
            session.handleInputString(text)
        }
    }
    
    public func deleteBackward() {
        guard let session = session else { return }
        // Standard ASCII DEL character (127 / \u{7f}) which Unix terminals interpret as Backspace
        session.pty.writeString("\u{7f}")
    }
    
    // Support hardware keyboard control keys and arrows
    public override var keyCommands: [UIKeyCommand]? {
        return [
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(handleArrow(_:))),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(handleArrow(_:))),
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(handleArrow(_:))),
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(handleArrow(_:))),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(handleEscape(_:))),
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(handleTab(_:)))
        ]
    }
    
    @objc private func handleArrow(_ sender: UIKeyCommand) {
        guard let session = session, let input = sender.input else { return }
        switch input {
        case UIKeyCommand.inputUpArrow:
            session.handleExtraKey("UP")
        case UIKeyCommand.inputDownArrow:
            session.handleExtraKey("DOWN")
        case UIKeyCommand.inputRightArrow:
            session.handleExtraKey("RIGHT")
        case UIKeyCommand.inputLeftArrow:
            session.handleExtraKey("LEFT")
        default:
            break
        }
    }
    
    @objc private func handleEscape(_ sender: UIKeyCommand) {
        session?.handleExtraKey("ESC")
    }
    
    @objc private func handleTab(_ sender: UIKeyCommand) {
        session?.handleExtraKey("TAB")
    }
}

public struct TerminalKeyboardRepresentable: UIViewRepresentable {
    @ObservedObject public var session: TerminalSession
    @Binding public var isKeyboardVisible: Bool
    
    public init(session: TerminalSession, isKeyboardVisible: Binding<Bool>) {
        self.session = session
        self._isKeyboardVisible = isKeyboardVisible
    }
    
    public func makeUIView(context: Context) -> TerminalKeyInputView {
        let view = TerminalKeyInputView(session: session)
        DispatchQueue.main.async {
            if isKeyboardVisible {
                view.becomeFirstResponder()
            }
        }
        return view
    }
    
    public func updateUIView(_ uiView: TerminalKeyInputView, context: Context) {
        uiView.session = session
        if isKeyboardVisible && !uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        } else if !isKeyboardVisible && uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.resignFirstResponder()
            }
        }
    }
}
