import Foundation

enum EditModeEnterTrigger {
    case longPress
    case optionKey
}

struct EditModeStateMachine {
    private(set) var isEditing = false
    private(set) var isOptionPressed = false
    private(set) var suppressOptionReenterEditing = false
    private var ignoreOptionEnterUntil: Date?

    mutating func syncExternalEditingState(_ isEditing: Bool) {
        self.isEditing = isEditing
    }

    mutating func enterEditingMode(trigger: EditModeEnterTrigger) -> Bool {
        guard !isEditing else { return false }
        if trigger == .optionKey, suppressOptionReenterEditing {
            return false
        }

        isEditing = true
        return true
    }

    mutating func exitEditingMode(userInitiated: Bool, optionPressedAtExit: Bool? = nil) -> Bool {
        guard isEditing else { return false }

        isEditing = false
        let optionIsPressed = optionPressedAtExit ?? isOptionPressed
        if userInitiated && optionIsPressed {
            suppressOptionReenterEditing = true
        }
        return true
    }

    mutating func forceExitEditingMode(userInitiated: Bool, optionPressedAtExit: Bool? = nil) {
        isEditing = false
        let optionIsPressed = optionPressedAtExit ?? isOptionPressed
        if userInitiated && optionIsPressed {
            suppressOptionReenterEditing = true
        }
        if userInitiated {
            ignoreOptionEnterUntil = Date().addingTimeInterval(0.25)
        }
    }

    mutating func handleOptionChanged(_ isPressed: Bool) -> Bool {
        let wasPressed = isOptionPressed
        isOptionPressed = isPressed

        if !isPressed {
            suppressOptionReenterEditing = false
            return false
        }

        let isRisingEdge = !wasPressed
        guard isRisingEdge else { return false }
        if let ignoreOptionEnterUntil, Date() < ignoreOptionEnterUntil {
            return false
        }

        return enterEditingMode(trigger: .optionKey)
    }
}
