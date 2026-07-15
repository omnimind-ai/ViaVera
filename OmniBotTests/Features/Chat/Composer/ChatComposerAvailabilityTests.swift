import Testing
@testable import Via_Vera

@Suite("Chat composer availability")
@MainActor
struct ChatComposerAvailabilityTests {
    @Test("A busy conversation still accepts the next draft")
    func busyConversationAllowsTextEntryWithoutSending() {
        let availability = ChatComposerAvailability(
            hasText: true,
            isBusy: true,
            isPreparingResend: false,
            isEditingUserMessage: false
        )

        #expect(availability.isTextEntryEnabled)
        #expect(!availability.canSend)
    }

    @Test("The drafted message becomes sendable when the response completes")
    func completedResponseEnablesSending() {
        let availability = ChatComposerAvailability(
            hasText: true,
            isBusy: false,
            isPreparingResend: false,
            isEditingUserMessage: false
        )

        #expect(availability.isTextEntryEnabled)
        #expect(availability.canSend)
    }

    @Test("Resend preparation temporarily locks composer editing")
    func resendPreparationLocksComposer() {
        let availability = ChatComposerAvailability(
            hasText: true,
            isBusy: true,
            isPreparingResend: true,
            isEditingUserMessage: true
        )

        #expect(!availability.isTextEntryEnabled)
        #expect(!availability.canSend)
    }
}
