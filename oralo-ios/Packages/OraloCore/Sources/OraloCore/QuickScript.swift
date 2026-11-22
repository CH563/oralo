import Foundation

public struct QuickScript: Equatable, Sendable {
    public let title: String
    public let text: String
    public let localeID: String

    /// Pass the app's resolved localization, never the keyboard or device region.
    public static func sample(localization: String) -> QuickScript {
        switch localization {
        case "zh-Hant":
            return QuickScript(title: "團隊季度匯報", text: """
            大家好，今天匯報本季的團隊進展。
            本季營收成長18%，交付週期縮短到12天。
            接下來，我們繼續夯實基礎，完善 roadmap。
            下一步，優先改善交付，明確每個 milestone 的負責人。
            客戶回饋顯示，穩定的交付比增加功能更加重要。
            我們計畫先解決三個最影響體驗的問題。
            第一個是減少等待，第二個是提高品質，第三個是及時回應。
            現在我想分享一個真實的團隊合作故事。
            回到計畫，下個月我們將完成第一輪客戶驗證。
            驗證之後，我們會根據回饋調整實施順序。
            最後重申，優先改善交付，同時守住品質底線。
            謝謝大家，接下來歡迎提問和討論。
            """, localeID: "zh-CN")
        case "zh-Hans":
            return QuickScript(title: "团队季度汇报", text: """
            大家好，今天汇报本季度的团队进展。
            本季度收入增长18%，交付周期缩短到12天。
            接下来，我们继续夯实基础，完善 roadmap。
            下一步，优先改善交付，明确每个 milestone 的负责人。
            客户反馈说明，稳定的交付比增加功能更加重要。
            我们计划先解决三个最影响体验的问题。
            第一个是减少等待，第二个是提高质量，第三个是及时反馈。
            现在我想分享一个真实的团队合作故事。
            回到计划，下个月我们将完成第一轮客户验证。
            验证之后，我们会根据反馈调整实施顺序。
            最后重申，优先改善交付，同时守住质量底线。
            谢谢大家，接下来欢迎提问和讨论。
            """, localeID: "zh-CN")
        default:
            return QuickScript(title: "Quarterly report", text: """
            Today I will walk you through our quarterly results.
            Revenue grew by eighteen percent and delivery now takes twelve days.
            Next, we will strengthen the foundation and refine our roadmap.
            Our next priority is delivery, with an owner for every milestone.
            Customer feedback tells us that reliable delivery matters more than adding features.
            We plan to tackle the three problems that most affect the experience.
            First we will reduce waiting, then improve quality, and finally make feedback faster.
            Let me share a story about how the team worked together.
            Returning to the plan, we will complete the first customer review next month.
            After the review, we will adjust our priorities based on the feedback.
            To close, delivery remains our priority without compromising quality.
            Thank you for listening and I look forward to your questions.
            """, localeID: "en-US")
        }
    }
}
