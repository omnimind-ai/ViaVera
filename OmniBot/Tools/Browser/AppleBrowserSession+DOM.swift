import Foundation
import WebKit

nonisolated struct AppleBrowserTypeTarget: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case selector
        case coordinates
        case activeElement
    }

    let kind: Kind
    let selector: String?
    let x: Int?
    let y: Int?
}

extension AppleBrowserSession {
    func click(
        _ arguments: OmniToolArguments,
        in tab: AppleBrowserTab
    ) async throws -> AppleBrowserOperationOutput {
        let selector = try arguments.optionalString("selector", maximumLength: 2_048)
        let x = try arguments.integer("coordinate_x", range: 0 ... 100_000)
        let y = try arguments.integer("coordinate_y", range: 0 ... 100_000)
        guard selector != nil || (x != nil && y != nil) else {
            throw AppleBrowserError.missingSelectorOrCoordinates
        }
        let payload = try await callJavaScript(
            in: tab,
            functionBody: Self.clickScript,
            arguments: [
                "selector": selector ?? NSNull(),
                "x": x ?? NSNull(),
                "y": y ?? NSNull(),
            ]
        )
        try await Task.sleep(for: .milliseconds(150))
        return AppleBrowserOperationOutput(
            summary: "Clicked an element using bounded DOM emulation.",
            payload: payload,
            metadata: domEmulationMetadata()
        )
    }

    func type(
        _ arguments: OmniToolArguments,
        in tab: AppleBrowserTab
    ) async throws -> AppleBrowserOperationOutput {
        let target = try Self.typeTarget(for: arguments)
        let text = try arguments.requiredString("text", maximumLength: 32_768)
        let payload = try await callJavaScript(
            in: tab,
            functionBody: Self.typeScript,
            arguments: [
                "selector": target.selector ?? NSNull(),
                "x": target.x ?? NSNull(),
                "y": target.y ?? NSNull(),
                "text": text,
            ]
        )
        return AppleBrowserOperationOutput(
            summary: "Entered text using bounded DOM emulation.",
            payload: payload,
            metadata: domEmulationMetadata()
        )
    }

    nonisolated static func typeTarget(
        for arguments: OmniToolArguments
    ) throws -> AppleBrowserTypeTarget {
        let selector = try arguments.optionalString("selector", maximumLength: 2_048)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let selector, !selector.isEmpty {
            return AppleBrowserTypeTarget(
                kind: .selector,
                selector: selector,
                x: nil,
                y: nil
            )
        }

        let x = try arguments.integer("coordinate_x", range: 0 ... 100_000)
        let y = try arguments.integer("coordinate_y", range: 0 ... 100_000)
        switch (x, y) {
        case let (.some(x), .some(y)):
            return AppleBrowserTypeTarget(
                kind: .coordinates,
                selector: nil,
                x: x,
                y: y
            )
        case (nil, nil):
            return AppleBrowserTypeTarget(
                kind: .activeElement,
                selector: nil,
                x: nil,
                y: nil
            )
        case (.some, nil), (nil, .some):
            throw AppleBrowserError.missingSelectorOrCoordinates
        }
    }

    nonisolated static var typeScriptSupportsCoordinateAndActiveElementTargets: Bool {
        typeScript.contains("document.elementFromPoint")
            && typeScript.contains("document.activeElement")
            && typeScript.contains("const element = selector")
    }

    func getText(
        _ arguments: OmniToolArguments,
        in tab: AppleBrowserTab
    ) async throws -> AppleBrowserOperationOutput {
        let selector = try arguments.optionalString("selector", maximumLength: 2_048)
        let keywords = try arguments.optionalString("keywords", maximumLength: 1_024)
        let fuzzy = try arguments.bool("fuzzy", default: true)
        let rawPayload = try await callJavaScript(
            in: tab,
            functionBody: Self.getTextScript,
            arguments: ["selector": selector ?? NSNull()]
        )
        let payload = filterTextPayload(rawPayload, keywords: keywords, fuzzy: fuzzy)
        return AppleBrowserOperationOutput(
            summary: "Read bounded text from the page DOM.",
            payload: payload,
            metadata: domReadMetadata()
        )
    }

    func scroll(
        _ arguments: OmniToolArguments,
        in tab: AppleBrowserTab
    ) async throws -> AppleBrowserOperationOutput {
        let amount = try arguments.integer(
            "amount",
            default: 500,
            range: 1 ... 100_000
        ) ?? 500
        let direction = try arguments.optionalString(
            "direction",
            default: "down",
            maximumLength: 8
        ) ?? "down"
        guard direction == "up" || direction == "down" else {
            throw OmniAgentToolError(
                "Invalid parameter 'direction': expected up or down."
            )
        }
        let payload = try await callJavaScript(
            in: tab,
            functionBody: Self.scrollScript,
            arguments: [
                "amount": amount,
                "direction": direction,
            ]
        )
        try await Task.sleep(for: .milliseconds(150))
        return AppleBrowserOperationOutput(
            summary: "Scrolled the page using JavaScript DOM control.",
            payload: payload,
            metadata: domEmulationMetadata()
        )
    }

    func getPageInfo(in tab: AppleBrowserTab) async throws -> AppleBrowserOperationOutput {
        let payload = try await callJavaScript(
            in: tab,
            functionBody: Self.pageInfoScript
        )
        return AppleBrowserOperationOutput(
            summary: "Read page and viewport metadata.",
            payload: payload,
            metadata: domReadMetadata()
        )
    }

    func executeJavaScript(
        _ arguments: OmniToolArguments,
        in tab: AppleBrowserTab
    ) async throws -> AppleBrowserOperationOutput {
        let script = try arguments.requiredString("script", maximumLength: 64 * 1_024)
        let payload = try await callJavaScript(
            in: tab,
            functionBody: Self.executeJavaScriptScript,
            arguments: ["source": script]
        )
        return AppleBrowserOperationOutput(
            summary: "Executed JavaScript in the WebKit page content world.",
            payload: payload,
            metadata: [
                "interactionMode": .string("javascript"),
                "trustedUserGesture": .bool(false),
            ]
        )
    }

    func findElements(
        _ arguments: OmniToolArguments,
        in tab: AppleBrowserTab
    ) async throws -> AppleBrowserOperationOutput {
        let selector = try arguments.requiredString("selector", maximumLength: 2_048)
        let payload = try await callJavaScript(
            in: tab,
            functionBody: Self.findElementsScript,
            arguments: ["selector": selector]
        )
        return AppleBrowserOperationOutput(
            summary: "Found up to 50 matching DOM elements.",
            payload: payload,
            metadata: domReadMetadata()
        )
    }

    func hover(
        _ arguments: OmniToolArguments,
        in tab: AppleBrowserTab
    ) async throws -> AppleBrowserOperationOutput {
        let selector = try arguments.optionalString("selector", maximumLength: 2_048)
        let x = try arguments.integer("coordinate_x", range: 0 ... 100_000)
        let y = try arguments.integer("coordinate_y", range: 0 ... 100_000)
        guard selector != nil || (x != nil && y != nil) else {
            throw AppleBrowserError.missingSelectorOrCoordinates
        }
        let payload = try await callJavaScript(
            in: tab,
            functionBody: Self.hoverScript,
            arguments: [
                "selector": selector ?? NSNull(),
                "x": x ?? NSNull(),
                "y": y ?? NSNull(),
            ]
        )
        return AppleBrowserOperationOutput(
            summary: "Hovered an element using synthetic DOM mouse events.",
            payload: payload,
            metadata: domEmulationMetadata()
        )
    }

    func getReadable(in tab: AppleBrowserTab) async throws -> AppleBrowserOperationOutput {
        let payload = try await callJavaScript(
            in: tab,
            functionBody: Self.readableScript
        )
        return AppleBrowserOperationOutput(
            summary: "Extracted readable text using a bounded article/main/body heuristic.",
            payload: payload,
            metadata: domReadMetadata().merging([
                "extractionMode": .string("heuristic"),
                "mozillaReadabilityEmbedded": .bool(false),
            ]) { current, _ in current }
        )
    }

    func getBackbone(
        _ arguments: OmniToolArguments,
        in tab: AppleBrowserTab
    ) async throws -> AppleBrowserOperationOutput {
        let maximumDepth = try arguments.integer(
            "max_depth",
            default: 4,
            range: 1 ... 12
        ) ?? 4
        let payload = try await callJavaScript(
            in: tab,
            functionBody: Self.backboneScript,
            arguments: ["maxDepth": maximumDepth]
        )
        return AppleBrowserOperationOutput(
            summary: "Extracted a bounded semantic DOM backbone.",
            payload: payload,
            metadata: domReadMetadata()
        )
    }

    func scrollAndCollect(
        _ arguments: OmniToolArguments,
        in tab: AppleBrowserTab
    ) async throws -> AppleBrowserOperationOutput {
        let selector = try arguments.requiredString("item_selector", maximumLength: 2_048)
        let scrollCount = try arguments.integer(
            "scroll_count",
            default: 3,
            range: 1 ... 20
        ) ?? 3
        let amount = try arguments.integer(
            "amount",
            default: 700,
            range: 1 ... 100_000
        ) ?? 700
        var values: [String] = []
        var seen = Set<String>()
        var stoppedForRisk = false

        for _ in 0 ..< scrollCount {
            let payload = try await callJavaScript(
                in: tab,
                functionBody: Self.collectScript,
                arguments: [
                    "selector": selector,
                    "amount": amount,
                ]
            )
            if case let .array(items) = payload {
                for case let .string(value) in items where seen.insert(value).inserted {
                    values.append(value)
                    if values.count == 200 { break }
                }
            }
            if values.count == 200 { break }
            try await Task.sleep(for: .milliseconds(250))
            if await assessRisk(on: tab).detected {
                stoppedForRisk = true
                break
            }
        }

        return AppleBrowserOperationOutput(
            summary: stoppedForRisk
                ? "Collection stopped after an anti-bot or human-verification challenge was detected."
                : "Collected \(values.count) unique item(s) while scrolling.",
            payload: .array(values.map(AgentValue.string)),
            metadata: domEmulationMetadata().merging([
                "collectionStoppedForRisk": .bool(stoppedForRisk),
                "maximumItems": .number(200),
            ]) { current, _ in current }
        )
    }

    func pressKey(
        _ arguments: OmniToolArguments,
        in tab: AppleBrowserTab
    ) async throws -> AppleBrowserOperationOutput {
        let key = try arguments.requiredString("key", maximumLength: 40)
        let payload = try await callJavaScript(
            in: tab,
            functionBody: Self.pressKeyScript,
            arguments: ["key": key]
        )
        return AppleBrowserOperationOutput(
            summary: "Dispatched a synthetic DOM keyboard event.",
            payload: payload,
            metadata: domEmulationMetadata()
        )
    }

    func waitForSelector(
        _ arguments: OmniToolArguments,
        in tab: AppleBrowserTab
    ) async throws -> AppleBrowserOperationOutput {
        let selector = try arguments.requiredString("selector", maximumLength: 2_048)
        let timeout = try arguments.integer(
            "timeout_ms",
            default: 5_000,
            range: 500 ... 30_000
        ) ?? 5_000
        let clock = ContinuousClock()
        let deadline = clock.now + .milliseconds(timeout)
        while clock.now < deadline {
            let payload = try await callJavaScript(
                in: tab,
                functionBody: Self.selectorExistsScript,
                arguments: ["selector": selector]
            )
            if payload == .bool(true) {
                return AppleBrowserOperationOutput(
                    summary: "The selector appeared before the timeout.",
                    payload: .object([
                        "selector": .string(selector),
                        "found": .bool(true),
                    ]),
                    metadata: domReadMetadata()
                )
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw AppleBrowserError.timedOut(action: "wait_for_selector", milliseconds: timeout)
    }

    func assessRisk(on tab: AppleBrowserTab) async -> AppleBrowserRiskReport {
        guard tab.page.url != nil else {
            tab.lastRiskReport = .clear
            return .clear
        }
        let value: AgentValue
        do {
            value = try await callJavaScript(
                in: tab,
                functionBody: Self.riskAssessmentScript
            )
        } catch {
            return tab.lastRiskReport
        }
        guard case let .object(object) = value,
              case let .bool(detected) = object["detected"],
              case let .array(rawSignals) = object["signals"] else {
            return tab.lastRiskReport
        }
        let signals = rawSignals.compactMap(\.stringValue)
        let report = AppleBrowserRiskReport(detected: detected, signals: signals)
        tab.lastRiskReport = report
        return report
    }

    func callJavaScript(
        in tab: AppleBrowserTab,
        functionBody: String,
        arguments: [String: Any] = [:]
    ) async throws -> AgentValue {
        let value = try await tab.page.callJavaScript(
            functionBody,
            arguments: arguments
        )
        return try agentValue(from: value)
    }

    func agentValue(from value: Any?) throws -> AgentValue {
        let wrapper: [String: Any] = ["value": value ?? NSNull()]
        guard JSONSerialization.isValidJSONObject(wrapper) else {
            return .string(String(describing: value ?? "undefined"))
        }
        let data = try JSONSerialization.data(withJSONObject: wrapper)
        guard data.count <= 128 * 1_024 else {
            throw AppleBrowserError.javaScriptResultTooLarge
        }
        let decoded = try JSONDecoder().decode(AgentValue.self, from: data)
        return decoded.objectValue?["value"] ?? .null
    }

    func filterTextPayload(
        _ payload: AgentValue,
        keywords: String?,
        fuzzy: Bool
    ) -> AgentValue {
        guard let keywords,
              !keywords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              case let .string(text) = payload else {
            return payload
        }
        let terms = keywords
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map(String.init)
        let matchingLines = text.split(separator: "\n").filter { line in
            terms.allSatisfy { term in
                if fuzzy {
                    line.localizedStandardContains(term)
                } else {
                    line.contains(term)
                }
            }
        }
        return .string(matchingLines.prefix(400).joined(separator: "\n"))
    }

    func domEmulationMetadata() -> [String: AgentValue] {
        [
            "interactionMode": .string("dom_emulation"),
            "nativeInput": .bool(false),
            "trustedUserGesture": .bool(false),
            "limitation": .string("Synthetic DOM events are not trusted native user gestures and may not activate protected browser flows."),
        ]
    }

    func domReadMetadata() -> [String: AgentValue] {
        [
            "interactionMode": .string("javascript_dom_read"),
            "nativeAccessibilityTree": .bool(false),
        ]
    }
}

private extension AppleBrowserSession {
    static let executeJavaScriptScript = #"""
    const AsyncFunction = Object.getPrototypeOf(async function() {}).constructor;
    let compiled;
    try {
        compiled = new AsyncFunction(`return (${source}\n);`);
    } catch (syntaxError) {
        compiled = new AsyncFunction(source);
    }
    return await compiled();
    """#

    static let clickScript = #"""
    const element = selector
        ? document.querySelector(selector)
        : document.elementFromPoint(Number(x), Number(y));
    if (!element) throw new Error("No matching element was found.");
    element.scrollIntoView({block: "center", inline: "center"});
    element.click();
    return {
        tag: element.tagName.toLowerCase(),
        id: element.id || null,
        text: (element.innerText || element.getAttribute("aria-label") || "").trim().slice(0, 500)
    };
    """#

    nonisolated static let typeScript = #"""
    const usesCoordinates = selector === null && x !== null && y !== null;
    const element = selector
        ? document.querySelector(selector)
        : (usesCoordinates
            ? document.elementFromPoint(Number(x), Number(y))
            : document.activeElement);
    if (!element || element === document.body) throw new Error("No editable element was found.");
    element.focus();
    if (element.isContentEditable) {
        element.textContent = text;
    } else if ("value" in element) {
        const prototype = element instanceof HTMLTextAreaElement
            ? HTMLTextAreaElement.prototype
            : HTMLInputElement.prototype;
        const setter = Object.getOwnPropertyDescriptor(prototype, "value")?.set;
        if (setter) setter.call(element, text); else element.value = text;
    } else {
        throw new Error("The selected element is not editable.");
    }
    element.dispatchEvent(new InputEvent("input", {bubbles: true, inputType: "insertText", data: text}));
    element.dispatchEvent(new Event("change", {bubbles: true}));
    return {tag: element.tagName.toLowerCase(), id: element.id || null, characterCount: text.length};
    """#

    static let getTextScript = #"""
    const element = selector ? document.querySelector(selector) : document.body;
    if (!element) throw new Error("No matching element was found.");
    return (element.innerText || element.textContent || "").trim().slice(0, 64000);
    """#

    static let scrollScript = #"""
    const delta = (direction === "up" ? -1 : 1) * Number(amount);
    window.scrollBy({top: delta, left: 0, behavior: "auto"});
    return {
        x: Math.round(window.scrollX),
        y: Math.round(window.scrollY),
        maximumY: Math.max(0, document.documentElement.scrollHeight - window.innerHeight)
    };
    """#

    static let pageInfoScript = #"""
    return {
        url: location.href.slice(0, 4096),
        title: (document.title || "").slice(0, 500),
        readyState: document.readyState,
        language: document.documentElement.lang || null,
        viewport: {width: window.innerWidth, height: window.innerHeight},
        document: {width: document.documentElement.scrollWidth, height: document.documentElement.scrollHeight},
        scroll: {x: Math.round(window.scrollX), y: Math.round(window.scrollY)},
        linkCount: document.links.length,
        formCount: document.forms.length,
        secureContext: window.isSecureContext
    };
    """#

    static let findElementsScript = #"""
    return Array.from(document.querySelectorAll(selector)).slice(0, 50).map((element, index) => {
        const rect = element.getBoundingClientRect();
        return {
            index,
            tag: element.tagName.toLowerCase(),
            id: element.id || null,
            classes: Array.from(element.classList).slice(0, 12),
            role: element.getAttribute("role"),
            ariaLabel: element.getAttribute("aria-label"),
            text: (element.innerText || element.value || "").trim().slice(0, 500),
            href: element.href || null,
            visible: rect.width > 0 && rect.height > 0,
            rect: {x: Math.round(rect.x), y: Math.round(rect.y), width: Math.round(rect.width), height: Math.round(rect.height)}
        };
    });
    """#

    static let hoverScript = #"""
    const element = selector
        ? document.querySelector(selector)
        : document.elementFromPoint(Number(x), Number(y));
    if (!element) throw new Error("No matching element was found.");
    const options = {bubbles: true, cancelable: true, view: window};
    element.dispatchEvent(new MouseEvent("mouseover", options));
    element.dispatchEvent(new MouseEvent("mouseenter", options));
    element.dispatchEvent(new MouseEvent("mousemove", options));
    return {tag: element.tagName.toLowerCase(), id: element.id || null};
    """#

    static let readableScript = #"""
    const root = document.querySelector("article") || document.querySelector("main") || document.body;
    const byline = document.querySelector('[rel="author"], .byline, [class*="author"]');
    return {
        title: (document.title || "").slice(0, 500),
        byline: byline ? (byline.innerText || "").trim().slice(0, 500) : null,
        text: (root?.innerText || "").trim().slice(0, 64000),
        sourceElement: root?.tagName?.toLowerCase() || null,
        url: location.href.slice(0, 4096)
    };
    """#

    static let backboneScript = #"""
    const accepted = new Set(["ARTICLE", "ASIDE", "BUTTON", "FOOTER", "FORM", "H1", "H2", "H3", "H4", "HEADER", "INPUT", "LI", "MAIN", "NAV", "OL", "P", "SECTION", "SELECT", "TABLE", "TEXTAREA", "UL"]);
    let count = 0;
    function visit(element, depth) {
        if (!element || depth > Number(maxDepth) || count >= 300) return null;
        count += 1;
        const children = [];
        for (const child of element.children) {
            const value = visit(child, depth + 1);
            if (value) children.push(value);
            if (count >= 300) break;
        }
        const landmark = accepted.has(element.tagName) || element.id || element.getAttribute("role") || element.getAttribute("aria-label");
        if (!landmark && children.length === 0) return null;
        return {
            tag: element.tagName.toLowerCase(),
            id: element.id || null,
            role: element.getAttribute("role"),
            label: element.getAttribute("aria-label"),
            text: accepted.has(element.tagName) ? (element.innerText || "").trim().slice(0, 160) : null,
            children
        };
    }
    return {nodeCount: count, tree: visit(document.body, 0)};
    """#

    static let collectScript = #"""
    const values = Array.from(document.querySelectorAll(selector)).slice(0, 200).map(element =>
        (element.innerText || element.textContent || "").trim().slice(0, 500)
    ).filter(Boolean);
    window.scrollBy({top: Number(amount), left: 0, behavior: "auto"});
    return values;
    """#

    static let pressKeyScript = #"""
    const element = document.activeElement && document.activeElement !== document.body
        ? document.activeElement
        : document.body;
    const options = {key, code: key, bubbles: true, cancelable: true};
    element.dispatchEvent(new KeyboardEvent("keydown", options));
    element.dispatchEvent(new KeyboardEvent("keyup", options));
    if (key === "Enter" && typeof element.click === "function") element.click();
    return {key, targetTag: element.tagName.toLowerCase(), targetId: element.id || null};
    """#

    static let selectorExistsScript = #"""
    return document.querySelector(selector) !== null;
    """#

    static let riskAssessmentScript = #"""
    const title = (document.title || "").toLowerCase();
    const text = (document.body?.innerText || "").slice(0, 16000).toLowerCase();
    const html = (document.documentElement?.innerHTML || "").slice(0, 100000).toLowerCase();
    const signals = [];
    const checks = [
        ["captcha", /captcha|hcaptcha|recaptcha/],
        ["human_verification", /verify (that )?you are human|human verification/],
        ["cloudflare_challenge", /checking your browser|cf-chl-|challenge-platform|attention required.*cloudflare/],
        ["unusual_traffic", /unusual traffic|automated queries/],
        ["access_challenge", /security check|bot detection|access denied|perimeterx|incapsula/]
    ];
    for (const [name, pattern] of checks) {
        if (pattern.test(title) || pattern.test(text)) signals.push(name);
    }
    if (/cf-chl-|challenge-platform/.test(html) && !signals.includes("cloudflare_challenge")) {
        signals.push("cloudflare_challenge");
    }
    const captchaElement = document.querySelector('iframe[src*="captcha" i], [class*="captcha" i], [id*="captcha" i]');
    if (captchaElement && captchaElement.getBoundingClientRect().height > 0) {
        if (!signals.includes("captcha")) signals.push("captcha");
    }
    return {detected: signals.length > 0, signals};
    """#
}
