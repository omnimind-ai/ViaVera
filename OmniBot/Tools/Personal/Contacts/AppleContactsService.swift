import Contacts
import Foundation

@MainActor
final class AppleContactsService {
    private let contactStore = CNContactStore()

    func search(_ arguments: OmniToolArguments) async throws -> AgentToolExecutionResult {
        let authorizationStatus = try await ensureAccess()
        let query = try arguments.requiredString("query", maximumLength: 4_096)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw OmniAgentToolError("Parameter 'query' must not be empty.")
        }
        let limit = try arguments.integer("limit", default: 25, range: 1...100) ?? 25
        let request = CNContactFetchRequest(keysToFetch: contactKeys)
        request.unifyResults = true
        var matches: [CNContact] = []
        try contactStore.enumerateContacts(with: request) { contact, stop in
            guard self.contactMatches(contact, query: query) else { return }
            matches.append(contact)
            if matches.count >= limit {
                stop.pointee = true
            }
        }

        return AgentToolExecutionResult(
            content: matches.isEmpty
                ? "No matching Apple contacts were found."
                : "Found \(matches.count) Apple contact(s).",
            metadata: [
                "contacts": .array(matches.map(contactValue)),
                "count": .number(Double(matches.count)),
                "authorizationStatus": .string(authorizationName(authorizationStatus)),
                "limitedAccess": .bool(isLimited(authorizationStatus)),
                "backend": .string("contacts"),
            ]
        )
    }

    func create(_ arguments: OmniToolArguments) async throws -> AgentToolExecutionResult {
        let authorizationStatus = try await ensureAccess()
        let givenName = try arguments.optionalString("givenName", maximumLength: 1_024) ?? ""
        let familyName = try arguments.optionalString("familyName", maximumLength: 1_024) ?? ""
        let organization = try arguments.optionalString("organization", maximumLength: 2_048) ?? ""
        let phones = try labeledValues(arguments, name: "phones", maximumCount: 32) ?? []
        let emails = try labeledValues(arguments, name: "emails", maximumCount: 32) ?? []
        guard [givenName, familyName, organization].contains(where: {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) || !phones.isEmpty || !emails.isEmpty else {
            throw OmniAgentToolError(
                "A new contact requires at least one name, organization, phone, or email value."
            )
        }

        let contact = CNMutableContact()
        contact.givenName = givenName
        contact.familyName = familyName
        contact.organizationName = organization
        contact.phoneNumbers = phoneLabeledValues(phones)
        contact.emailAddresses = emailLabeledValues(emails)
        let saveRequest = CNSaveRequest()
        saveRequest.add(contact, toContainerWithIdentifier: nil)
        try contactStore.execute(saveRequest)

        return AgentToolExecutionResult(
            content: "Apple contact created.",
            metadata: [
                "contact": contactValue(contact),
                "created": .bool(true),
                "authorizationStatus": .string(authorizationName(authorizationStatus)),
                "limitedAccess": .bool(isLimited(authorizationStatus)),
                "backend": .string("contacts"),
            ]
        )
    }

    func update(_ arguments: OmniToolArguments) async throws -> AgentToolExecutionResult {
        let authorizationStatus = try await ensureAccess()
        let identifier = try arguments.requiredString("contactId", maximumLength: 512)
        let existingContact: CNContact
        do {
            existingContact = try contactStore.unifiedContact(
                withIdentifier: identifier,
                keysToFetch: contactKeys
            )
        } catch {
            if isLimited(authorizationStatus) {
                throw limitedScopeError(contactID: identifier)
            }
            throw ApplePersonalToolError(
                "No accessible Apple contact exists with id '\(identifier)'.",
                code: "not_found",
                backend: "contacts"
            )
        }
        guard let contact = existingContact.mutableCopy() as? CNMutableContact else {
            throw ApplePersonalToolError(
                "The selected contact cannot be edited.",
                code: "read_only",
                backend: "contacts"
            )
        }

        var changed = false
        if arguments.values["givenName"] != nil {
            contact.givenName = try arguments.optionalString(
                "givenName",
                default: "",
                maximumLength: 1_024
            ) ?? ""
            changed = true
        }
        if arguments.values["familyName"] != nil {
            contact.familyName = try arguments.optionalString(
                "familyName",
                default: "",
                maximumLength: 1_024
            ) ?? ""
            changed = true
        }
        if arguments.values["organization"] != nil {
            contact.organizationName = try arguments.optionalString(
                "organization",
                default: "",
                maximumLength: 2_048
            ) ?? ""
            changed = true
        }
        if let phones = try labeledValues(arguments, name: "phones", maximumCount: 32) {
            contact.phoneNumbers = phoneLabeledValues(phones)
            changed = true
        }
        if let emails = try labeledValues(arguments, name: "emails", maximumCount: 32) {
            contact.emailAddresses = emailLabeledValues(emails)
            changed = true
        }
        guard changed else {
            throw OmniAgentToolError("No contact fields were supplied to update.")
        }

        let saveRequest = CNSaveRequest()
        saveRequest.update(contact)
        try contactStore.execute(saveRequest)
        return AgentToolExecutionResult(
            content: "Apple contact updated.",
            metadata: [
                "contact": contactValue(contact),
                "updated": .bool(true),
                "authorizationStatus": .string(authorizationName(authorizationStatus)),
                "limitedAccess": .bool(isLimited(authorizationStatus)),
                "backend": .string("contacts"),
            ]
        )
    }

    func delete(_ arguments: OmniToolArguments) async throws -> AgentToolExecutionResult {
        let authorizationStatus = try await ensureAccess()
        let identifier = try arguments.requiredString("contactId", maximumLength: 512)
        let existingContact: CNContact
        do {
            existingContact = try contactStore.unifiedContact(
                withIdentifier: identifier,
                keysToFetch: contactKeys
            )
        } catch {
            if isLimited(authorizationStatus) {
                throw limitedScopeError(contactID: identifier)
            }
            throw ApplePersonalToolError(
                "No accessible Apple contact exists with id '\(identifier)'.",
                code: "not_found",
                backend: "contacts"
            )
        }
        guard let contact = existingContact.mutableCopy() as? CNMutableContact else {
            throw ApplePersonalToolError(
                "The selected contact cannot be deleted.",
                code: "read_only",
                backend: "contacts"
            )
        }
        let saveRequest = CNSaveRequest()
        saveRequest.delete(contact)
        try contactStore.execute(saveRequest)
        return AgentToolExecutionResult(
            content: "Apple contact deleted.",
            metadata: [
                "contactId": .string(identifier),
                "deleted": .bool(true),
                "authorizationStatus": .string(authorizationName(authorizationStatus)),
                "limitedAccess": .bool(isLimited(authorizationStatus)),
                "backend": .string("contacts"),
            ]
        )
    }

    private var contactKeys: [CNKeyDescriptor] {
        [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactMiddleNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        ]
    }

    private func ensureAccess() async throws -> CNAuthorizationStatus {
        var status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .notDetermined {
            _ = try await contactStore.requestAccess(for: .contacts)
            status = CNContactStore.authorizationStatus(for: .contacts)
        }
        guard status == .authorized || isLimited(status) else {
            throw ApplePersonalToolError(
                "Contacts access is not authorized. Enable Contacts access for OmniBot in Settings.",
                code: "permission_denied",
                permission: "contacts",
                authorizationStatus: authorizationName(status),
                backend: "contacts",
                requiresSystemSettings: status == .denied || status == .restricted
            )
        }
        return status
    }

    private func limitedScopeError(contactID: String) -> ApplePersonalToolError {
        ApplePersonalToolError(
            "Contact '\(contactID)' is outside OmniBot's limited Contacts selection. Expand OmniBot's Contacts access in Settings before retrying.",
            code: "limited_scope",
            permission: "contacts",
            authorizationStatus: "limited",
            backend: "contacts",
            requiresSystemSettings: true,
            guidance: "Do not retry automatically. Ask the user to expand OmniBot's selected Contacts access in system Settings."
        )
    }

    private func isLimited(_ status: CNAuthorizationStatus) -> Bool {
        #if os(iOS)
        status == .limited
        #else
        false
        #endif
    }

    private func authorizationName(_ status: CNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "not_determined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .authorized: "authorized"
        #if os(iOS)
        case .limited: "limited"
        #endif
        @unknown default: "unknown"
        }
    }

    private func labeledValues(
        _ arguments: OmniToolArguments,
        name: String,
        maximumCount: Int
    ) throws -> [AppleContactLabeledValue]? {
        guard let rawValue = arguments.values[name] else { return nil }
        if rawValue == .null { return [] }
        guard case let .array(values) = rawValue, values.count <= maximumCount else {
            throw OmniAgentToolError(
                "Invalid parameter '\(name)': expected at most \(maximumCount) labeled values."
            )
        }
        return try values.map { value in
            guard case let .object(object) = value,
                  case let .string(label)? = object["label"],
                  case let .string(rawString)? = object["value"] else {
                throw OmniAgentToolError(
                    "Invalid parameter '\(name)': every item must contain string 'label' and 'value' fields."
                )
            }
            let normalizedValue = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedValue.isEmpty else {
                throw OmniAgentToolError(
                    "Invalid parameter '\(name)': labeled values must not be empty."
                )
            }
            return AppleContactLabeledValue(
                label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                value: normalizedValue
            )
        }
    }

    private func phoneLabeledValues(
        _ values: [AppleContactLabeledValue]
    ) -> [CNLabeledValue<CNPhoneNumber>] {
        values.map { item in
            CNLabeledValue(
                label: contactLabel(item.label, isPhone: true),
                value: CNPhoneNumber(stringValue: item.value)
            )
        }
    }

    private func emailLabeledValues(
        _ values: [AppleContactLabeledValue]
    ) -> [CNLabeledValue<NSString>] {
        values.map { item in
            CNLabeledValue(
                label: contactLabel(item.label, isPhone: false),
                value: item.value as NSString
            )
        }
    }

    private func contactLabel(_ label: String, isPhone: Bool) -> String? {
        switch label.lowercased() {
        case "": nil
        case "home": CNLabelHome
        case "work": CNLabelWork
        case "other": CNLabelOther
        case "mobile" where isPhone: CNLabelPhoneNumberMobile
        case "iphone" where isPhone: CNLabelPhoneNumberiPhone
        case "main" where isPhone: CNLabelPhoneNumberMain
        case "pager" where isPhone: CNLabelPhoneNumberPager
        case "home_fax" where isPhone: CNLabelPhoneNumberHomeFax
        case "work_fax" where isPhone: CNLabelPhoneNumberWorkFax
        case "other_fax" where isPhone: CNLabelPhoneNumberOtherFax
        default: label
        }
    }

    private func contactMatches(_ contact: CNContact, query: String) -> Bool {
        var candidates = [
            CNContactFormatter.string(from: contact, style: .fullName) ?? "",
            contact.givenName,
            contact.middleName,
            contact.familyName,
            contact.organizationName,
        ]
        candidates.append(contentsOf: contact.phoneNumbers.map(\.value.stringValue))
        candidates.append(contentsOf: contact.emailAddresses.map { $0.value as String })
        return candidates.contains { $0.localizedStandardContains(query) }
    }

    private func contactValue(_ contact: CNContact) -> AgentValue {
        .object([
            "contactId": .string(contact.identifier),
            "displayName": .string(
                CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            ),
            "givenName": .string(contact.givenName),
            "middleName": .string(contact.middleName),
            "familyName": .string(contact.familyName),
            "organization": .string(contact.organizationName),
            "phones": .array(contact.phoneNumbers.map { item in
                .object([
                    "label": .string(outputLabel(item.label)),
                    "value": .string(item.value.stringValue),
                ])
            }),
            "emails": .array(contact.emailAddresses.map { item in
                .object([
                    "label": .string(outputLabel(item.label)),
                    "value": .string(item.value as String),
                ])
            }),
        ])
    }

    private func outputLabel(_ label: String?) -> String {
        switch label {
        case CNLabelHome: "home"
        case CNLabelWork: "work"
        case CNLabelOther: "other"
        case CNLabelPhoneNumberMobile: "mobile"
        case CNLabelPhoneNumberiPhone: "iphone"
        case CNLabelPhoneNumberMain: "main"
        case CNLabelPhoneNumberPager: "pager"
        case CNLabelPhoneNumberHomeFax: "home_fax"
        case CNLabelPhoneNumberWorkFax: "work_fax"
        case CNLabelPhoneNumberOtherFax: "other_fax"
        case let label?: label
        case nil: "other"
        }
    }
}
