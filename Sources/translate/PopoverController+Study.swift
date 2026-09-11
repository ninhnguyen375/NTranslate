// The real macOS menu bar, and the activation policy that makes it appear.
//
// NTranslate launches as an accessory app: no Dock icon, no menu bar, `NSApp.mainMenu` alive only
// so its key equivalents keep working. The Study window is the one place that wants a full app
// around it, so opening it promotes the process to `.regular` and closing it drops back.
import AppKit

extension PopoverController {
    static let studyMenuTagBase = 9100

    enum StudyMenuCommand: Int, CaseIterable {
        case start = 9101
        case newWords = 9102
        case showAnswer = 9103
        case gradeAgain = 9104
        case gradeHard = 9105
        case gradeEasy = 9106
        case undo = 9107
        case skip = 9108
        case reading = 9109
        case passages = 9110
        case home = 9111

        var title: String {
            switch self {
            case .start: return "Start Learning"
            case .newWords: return "Learn New Words"
            case .showAnswer: return "Show Answer"
            case .gradeAgain: return "Grade: Again"
            case .gradeHard: return "Grade: Hard"
            case .gradeEasy: return "Grade: Easy"
            case .undo: return "Undo Grade"
            case .skip: return "Remove Card from Deck"
            case .reading: return "Reading Passage"
            case .passages: return "Saved Passages"
            case .home: return "Back to Home"
            }
        }

        /// Key equivalents are Command-based here so they never fight the bare 1/2/3 the card view
        /// already listens for.
        var key: (String, NSEvent.ModifierFlags) {
            switch self {
            case .start: return ("\r", .command)
            case .newWords: return ("n", .command)
            case .showAnswer: return ("", [])
            case .gradeAgain: return ("1", .command)
            case .gradeHard: return ("2", .command)
            case .gradeEasy: return ("3", .command)
            case .undo: return ("z", .command)
            case .skip: return ("\u{8}", .command)
            case .reading: return ("r", .command)
            case .passages: return ("r", [.command, .shift])
            case .home: return ("0", .command)
            }
        }

        var controllerCommand: ReviewWindowController.StudyCommand {
            switch self {
            case .start: return .start
            case .newWords: return .newWords
            case .showAnswer: return .showAnswer
            case .gradeAgain, .gradeHard, .gradeEasy: return .grade
            case .undo: return .undo
            case .skip: return .skip
            case .reading: return .reading
            case .passages: return .passages
            case .home: return .home
            }
        }

        var grade: SRSGrade? {
            switch self {
            case .gradeAgain: return .again
            case .gradeHard: return .hard
            case .gradeEasy: return .easy
            default: return nil
            }
        }
    }

    func buildStudyMenu() -> NSMenu {
        let menu = NSMenu(title: "Study")
        for command in StudyMenuCommand.allCases {
            if command == .gradeAgain || command == .reading { menu.addItem(.separator()) }
            let item = NSMenuItem(title: command.title, action: #selector(studyMenuCommand(_:)), keyEquivalent: command.key.0)
            item.keyEquivalentModifierMask = command.key.1
            item.tag = command.rawValue
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    @objc func studyMenuCommand(_ sender: NSMenuItem) {
        guard let command = StudyMenuCommand(rawValue: sender.tag) else { return }
        if !(reviewWindowController.window?.isVisible ?? false) {
            openReviewWindow()
        }
        reviewWindowController.runStudyCommand(command.controllerCommand, grade: command.grade)
    }

    @objc func showKeyboardShortcuts() {
        let alert = NSAlert()
        alert.messageText = "Keyboard shortcuts"
        alert.informativeText = """
        Study window
        • Space - show the answer, then cycle-scroll the card
        • Enter - continue after an auto-graded answer
        • 1 / 2 / 3 - Again / Hard / Easy, or pick between two words
        • 4 / 5 - speak the term, speak it slowly
        • 6 - open the card in the translate panel
        • Cmd+Z - undo the last grade
        • Esc - leave the current screen, then close the window

        Learn New Words
        • 1 / 2 / 3 - Known / Learn / Skip
        • 4 / 5 - speak the word, speak it slowly
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Promote to a full app so the Study window gets the menu bar and Dock icon it needs. The
    /// promotion happens after the window is on screen: switching first steals focus from whatever
    /// the learner was reading, and the translate panel is non-activating on purpose.
    func promoteForStudyWindow() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        reviewWindowController.window?.makeKeyAndOrderFront(nil)
    }

    /// Back to a menu-bar utility once the Study window is gone.
    func demoteAfterStudyWindow() {
        guard NSApp.activationPolicy() != .accessory else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}

extension PopoverController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let command = StudyMenuCommand(rawValue: menuItem.tag) else { return true }
        guard let review = _reviewWindowController, review.window?.isVisible == true else {
            return command == .start || command == .newWords
        }
        return review.canRunStudyCommand(command.controllerCommand)
    }
}
