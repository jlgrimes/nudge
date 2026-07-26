import Foundation

extension NudgeStore {
    static func demoNudges() -> [NudgeItem] {
        let twoDays = Calendar.current.date(byAdding: .day, value: 2, to: .now) ?? .now
        let messaging = ContextTrigger(
            kind: .messaging,
            identifiers: [
                "com.tinyspeck.slackmacgap",
                "com.apple.MobileSMS",
                "com.microsoft.teams2",
                "slack.com"
            ],
            confidence: 0.87,
            source: .inferred
        )
        let shopping = ContextTrigger(
            kind: .onlineShopping,
            identifiers: ["amazon.com", "ebay.com", "walmart.com", "etsy.com", "target.com"],
            confidence: 0.9,
            source: .inferred
        )
        let calendar = ContextTrigger(
            kind: .calendar,
            identifiers: ["calendar.urgent"],
            confidence: 1,
            source: .explicit
        )

        return [
            NudgeItem(
                originalRequest: "Remind me to send Maya the final mockup",
                title: "Send Maya the final mockup",
                detail: "When you’re messaging",
                triggers: [messaging],
                fallbackAt: twoDays,
                status: .active
            ),
            NudgeItem(
                originalRequest: "Remind me to message Alex",
                title: "Message Alex",
                detail: "When you’re messaging",
                triggers: [messaging],
                fallbackAt: twoDays
            ),
            NudgeItem(
                originalRequest: "Remind me to order coffee filters",
                title: "Order coffee filters",
                detail: "While you’re shopping online",
                triggers: [shopping],
                fallbackAt: twoDays,
                primaryURL: URL(string: "https://amazon.com")
            ),
            NudgeItem(
                originalRequest: "Leave for the dentist",
                title: "Leave for the dentist",
                detail: "12 min drive · appointment at 2:00",
                priority: .urgent,
                triggers: [calendar],
                fallbackAt: .now,
                canInterruptFocus: true
            )
        ]
    }

    static func dayScenarioNudges() -> [NudgeItem] {
        let context = ContextTrigger(
            kind: .productivity,
            identifiers: ["mock.day"],
            confidence: 1,
            source: .inferred
        )
        let messaging = ContextTrigger(
            kind: .messaging,
            identifiers: ["com.tinyspeck.slackmacgap", "com.apple.MobileSMS"],
            confidence: 0.87,
            source: .inferred
        )
        let calendar = ContextTrigger(
            kind: .calendar,
            identifiers: ["mock.calendar"],
            confidence: 1,
            source: .inferred
        )
        let fallback = Calendar.current.date(byAdding: .day, value: 2, to: .now) ?? .now

        return [
            NudgeItem(
                originalRequest: "Morning overview",
                title: "Plan the three things that matter today",
                detail: "Morning overview",
                priority: .informational,
                triggers: [context],
                fallbackAt: fallback,
                createdAt: mockDate(hour: 8, minute: 30),
                status: .active
            ),
            NudgeItem(
                originalRequest: "Prepare for design review",
                title: "Prepare for the design review",
                detail: "Meeting in 40 minutes",
                triggers: [calendar],
                fallbackAt: fallback,
                createdAt: mockDate(hour: 9, minute: 20),
                status: .active
            ),
            NudgeItem(
                originalRequest: "Message Alex",
                title: "Message Alex about the launch",
                detail: "Slack became active",
                triggers: [messaging],
                fallbackAt: fallback,
                createdAt: mockDate(hour: 10, minute: 5),
                status: .active,
                invocation: .contextual(.messaging)
            ),
            NudgeItem(
                originalRequest: "Submit lunch order",
                title: "Submit the team lunch order",
                detail: "Ordering closes soon",
                priority: .urgent,
                triggers: [context],
                fallbackAt: fallback,
                createdAt: mockDate(hour: 11, minute: 45),
                status: .active,
                canInterruptFocus: true
            ),
            NudgeItem(
                originalRequest: "Review afternoon",
                title: "Your afternoon is meeting-free",
                detail: "A good time for focused work",
                priority: .informational,
                triggers: [calendar],
                fallbackAt: fallback,
                createdAt: mockDate(hour: 14, minute: 30),
                status: .active
            ),
            NudgeItem(
                originalRequest: "Wrap up",
                title: "Capture loose ends before signing off",
                detail: "End-of-day review",
                triggers: [context],
                fallbackAt: fallback,
                createdAt: mockDate(hour: 17, minute: 15),
                status: .active
            )
        ]
    }

    static func singleScenarioTimeline() -> [NudgeItem] {
        let messaging = ContextTrigger(
            kind: .messaging,
            identifiers: ["com.tinyspeck.slackmacgap", "com.apple.MobileSMS", "com.microsoft.teams2"],
            confidence: 0.87,
            source: .inferred
        )
        let context = ContextTrigger(
            kind: .productivity,
            identifiers: ["mock.single"],
            confidence: 1,
            source: .inferred
        )
        let fallback = Calendar.current.date(byAdding: .day, value: 2, to: .now) ?? .now
        let now = Date.now

        return [
            NudgeItem(
                originalRequest: "Review launch notes",
                title: "Review the launch notes",
                detail: "",
                triggers: [context],
                fallbackAt: fallback,
                createdAt: now.addingTimeInterval(-900),
                status: .active
            ),
            NudgeItem(
                originalRequest: "Message Alex",
                title: "Message Alex",
                detail: "",
                triggers: [messaging],
                fallbackAt: fallback,
                createdAt: now.addingTimeInterval(-2_400),
                status: .pending
            )
        ]
    }

    static func settledScenarioNudges() -> [NudgeItem] {
        Array(dayScenarioNudges().prefix(2))
    }

    static func multipleScenarioNudges() -> [NudgeItem] {
        let context = ContextTrigger(
            kind: .productivity,
            identifiers: ["mock.batch"],
            confidence: 1,
            source: .inferred
        )
        let fallback = Calendar.current.date(byAdding: .day, value: 2, to: .now) ?? .now
        return [
            NudgeItem(
                originalRequest: "Join design review",
                title: "Join the design review",
                detail: "Starts in 5 minutes",
                priority: .urgent,
                triggers: [context],
                fallbackAt: fallback,
                status: .active,
                canInterruptFocus: true
            ),
            NudgeItem(
                originalRequest: "Send prototype link",
                title: "Send the prototype link to Maya",
                detail: "Slack is active",
                triggers: [context],
                fallbackAt: fallback,
                status: .active
            ),
            NudgeItem(
                originalRequest: "Order coffee filters",
                title: "Order coffee filters",
                detail: "Shopping tab is open",
                triggers: [context],
                fallbackAt: fallback,
                status: .active
            ),
            NudgeItem(
                originalRequest: "Afternoon status",
                title: "Your afternoon is meeting-free",
                detail: "Informational",
                priority: .informational,
                triggers: [context],
                fallbackAt: fallback,
                status: .active
            )
        ]
    }

    static func focusScenarioNudges() -> [NudgeItem] {
        let context = ContextTrigger(
            kind: .productivity,
            identifiers: ["mock.focus"],
            confidence: 1,
            source: .inferred
        )
        let fallback = Calendar.current.date(byAdding: .day, value: 2, to: .now) ?? .now
        return [
            NudgeItem(
                originalRequest: "Message Alex",
                title: "Message Alex about the launch",
                detail: "Held during Focus",
                triggers: [context],
                fallbackAt: fallback,
                status: .deferred,
                surfacedAt: Date.now.addingTimeInterval(-120)
            ),
            NudgeItem(
                originalRequest: "Order coffee filters",
                title: "Order coffee filters",
                detail: "Held during Focus",
                triggers: [context],
                fallbackAt: fallback,
                status: .deferred,
                surfacedAt: Date.now.addingTimeInterval(-60)
            ),
            NudgeItem(
                originalRequest: "Leave for dentist",
                title: "Leave for the dentist",
                detail: "Urgent · appointment at 2:00",
                priority: .urgent,
                triggers: [context],
                fallbackAt: .now,
                status: .active,
                canInterruptFocus: true
            )
        ]
    }

    private static func mockDate(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }
}
