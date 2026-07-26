import Foundation
import XCTest
@testable import Nudge

final class V1FoundationTests: XCTestCase {
    func testInstalledApplicationCatalogDiscoversApplicationBundles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NudgeAppCatalog-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let applicationURL = root.appendingPathComponent("Example.app", isDirectory: true)
        let contentsURL = applicationURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(
            at: contentsURL,
            withIntermediateDirectories: true
        )
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.example.app",
            "CFBundleName": "Example",
            "CFBundlePackageType": "APPL"
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))

        let catalog = InstalledApplicationCatalog(searchRoots: [root])
        let applications = await catalog.applications()

        XCTAssertEqual(applications.count, 1)
        XCTAssertEqual(applications.first?.bundleIdentifier, "com.example.app")
        XCTAssertEqual(applications.first?.name, "Example")
        XCTAssertEqual(applications.first?.applicationURL, applicationURL.standardizedFileURL)
    }

    func testMockProviderTargetsNamedInstalledApplication() async throws {
        let discord = InstalledApplicationDescriptor(
            bundleIdentifier: "com.hnc.Discord",
            name: "Discord",
            applicationURL: URL(fileURLWithPath: "/Applications/Discord.app")
        )
        let service = NudgeInferenceService(
            provider: MockLLMInferenceProvider(),
            applicationCatalog: StaticInstalledApplicationCatalog(values: [discord])
        )

        let response = try await service.infer(
            text: "Remind me to check the tournament chat when I open Discord",
            fallbackDays: 2
        )

        guard
            let firstCondition = response.result.conditions.first,
            case .applicationActivated(let bundleIdentifier, let applicationName) = firstCondition
        else {
            return XCTFail("Expected an exact application condition")
        }
        XCTAssertEqual(bundleIdentifier, "com.hnc.Discord")
        XCTAssertEqual(applicationName, "Discord")

        guard case .openApplication(let actionBundleID, let actionName, let applicationURL) =
            response.result.action
        else {
            return XCTFail("Expected an open-application action")
        }
        XCTAssertEqual(actionBundleID, "com.hnc.Discord")
        XCTAssertEqual(actionName, "Discord")
        XCTAssertEqual(applicationURL, discord.applicationURL)
    }

    func testApplicationMentionResolverRequiresNameBoundaries() {
        let mail = InstalledApplicationDescriptor(
            bundleIdentifier: "com.apple.mail",
            name: "Mail",
            applicationURL: URL(fileURLWithPath: "/System/Applications/Mail.app")
        )
        let arc = InstalledApplicationDescriptor(
            bundleIdentifier: "company.thebrowser.Browser",
            name: "Arc",
            applicationURL: URL(fileURLWithPath: "/Applications/Arc.app")
        )

        XCTAssertNil(
            ApplicationMentionResolver.bestMatch(
                in: "Remind me to email Alex after I search",
                applications: [mail, arc]
            )
        )
        XCTAssertEqual(
            ApplicationMentionResolver.bestMatch(
                in: "Remind me when I open Mail",
                applications: [mail, arc]
            )?.bundleIdentifier,
            "com.apple.mail"
        )
    }

    @MainActor
    func testExactApplicationConditionSurfacesOnlyForThatApplication() {
        let item = NudgeItem(
            originalRequest: "Check the tournament chat in Discord",
            title: "Check the tournament chat",
            detail: "When Discord is active",
            conditions: [
                .applicationActivated(
                    bundleIdentifier: "com.hnc.Discord",
                    applicationName: "Discord"
                )
            ],
            fallbackAt: Date.now.addingTimeInterval(3_600),
            action: .openApplication(
                bundleIdentifier: "com.hnc.Discord",
                applicationName: "Discord",
                applicationURL: URL(fileURLWithPath: "/Applications/Discord.app")
            )
        )
        let store = NudgeStore(seedDemoData: false)
        store.nudges = [item]

        store.receive(
            context: ContextEvent.activatedApplication(
                bundleIdentifier: "com.apple.Safari",
                name: "Safari"
            )
        )
        XCTAssertEqual(store.nudges.first?.status, .pending)

        store.receive(
            context: ContextEvent.activatedApplication(
                bundleIdentifier: "com.hnc.Discord",
                name: "Discord"
            )
        )
        XCTAssertEqual(store.nudges.first?.status, .active)
        XCTAssertEqual(store.nudges.first?.invocation, .contextual(.application))
    }

    func testAppleDraftCanSelectOnlyAnInstalledApplication() throws {
        let installed = InstalledApplicationDescriptor(
            bundleIdentifier: "com.figma.Desktop",
            name: "Figma",
            applicationURL: URL(fileURLWithPath: "/Applications/Figma.app")
        )
        let request = NudgeInferenceRequest(
            text: "Review the mockup when I open Figma",
            fallbackDays: 2,
            installedApplications: [installed]
        )
        let valid = AppleIntelligenceDraft(
            title: "Review the mockup",
            detail: "",
            priority: .actionable,
            context: .productivity,
            identifiers: ["context:any-work"],
            source: .explicit,
            confidence: 0.95,
            hasPrimaryURL: false,
            primaryURL: "",
            canInterruptFocus: false,
            hasExplicitFallback: false,
            fallbackDelayMinutes: 0,
            hasTargetApplication: true,
            targetApplicationBundleIdentifier: "com.figma.Desktop"
        )
        let invented = AppleIntelligenceDraft(
            title: "Review the mockup",
            detail: "",
            priority: .actionable,
            context: .productivity,
            identifiers: ["context:any-work"],
            source: .explicit,
            confidence: 0.95,
            hasPrimaryURL: false,
            primaryURL: "",
            canInterruptFocus: false,
            hasExplicitFallback: false,
            fallbackDelayMinutes: 0,
            hasTargetApplication: true,
            targetApplicationBundleIdentifier: "com.example.invented"
        )

        let validResult = try AppleIntelligenceInferenceProvider.map(valid, request: request)
        guard
            let validCondition = validResult.conditions.first,
            case .applicationActivated(let bundleIdentifier, _) = validCondition
        else {
            return XCTFail("Expected exact installed-app condition")
        }
        XCTAssertEqual(bundleIdentifier, "com.figma.Desktop")
        XCTAssertEqual(validResult.primaryURL, installed.applicationURL)

        let inventedResult = try AppleIntelligenceInferenceProvider.map(invented, request: request)
        guard
            let inventedCondition = inventedResult.conditions.first,
            case .context(let fallbackTrigger) = inventedCondition
        else {
            return XCTFail("Invented app should fall back to a validated broad context")
        }
        XCTAssertEqual(fallbackTrigger.kind, .productivity)
        XCTAssertEqual(inventedResult.action, .none)
    }

    func testLegacySnapshotPayloadMigratesToConditionAndAction() throws {
        let legacy = LegacyNudgePayload(
            id: UUID(),
            originalRequest: "Buy filters",
            title: "Buy filters",
            detail: "On Amazon",
            priority: .actionable,
            triggers: [
                ContextTrigger(
                    kind: .onlineShopping,
                    identifiers: ["amazon.com"],
                    confidence: 1,
                    source: .explicit
                )
            ],
            fallbackAt: Date.now.addingTimeInterval(3_600),
            createdAt: .now,
            status: .pending,
            surfacedAt: nil,
            invocation: .temporal,
            primaryURL: URL(string: "https://amazon.com"),
            canInterruptFocus: false
        )

        let decoded = try JSONDecoder().decode(
            NudgeItem.self,
            from: JSONEncoder().encode(legacy)
        )

        guard
            let decodedCondition = decoded.conditions.first,
            case .context(let trigger) = decodedCondition
        else {
            return XCTFail("Expected migrated context condition")
        }
        XCTAssertEqual(trigger.kind, .onlineShopping)
        XCTAssertEqual(decoded.action, .openURL(URL(string: "https://amazon.com")!))
    }
}

private struct LegacyNudgePayload: Codable {
    let id: UUID
    let originalRequest: String
    let title: String
    let detail: String
    let priority: NudgePriority
    let triggers: [ContextTrigger]
    let fallbackAt: Date
    let createdAt: Date
    let status: NudgeStatus
    let surfacedAt: Date?
    let invocation: NudgeInvocation
    let primaryURL: URL?
    let canInterruptFocus: Bool
}
