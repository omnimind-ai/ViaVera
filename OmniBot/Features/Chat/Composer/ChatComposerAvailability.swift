struct ChatComposerAvailability {
    let hasText: Bool
    let isBusy: Bool
    let isPreparingResend: Bool
    let isEditingUserMessage: Bool

    var isTextEntryEnabled: Bool {
        !isPreparingResend
    }

    var canSend: Bool {
        hasText
            && !isPreparingResend
            && (!isBusy || isEditingUserMessage)
    }
}
