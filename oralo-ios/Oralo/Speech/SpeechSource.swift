import Foundation
import OraloCore

nonisolated enum SpeechEvent: Sendable {
    case preparing(String)
    case started(id: UUID, engine: String)
    case transcript(id: UUID, text: String, isFinal: Bool, deliveryDelay: TimeInterval?)
    case level(Float, duration: TimeInterval = 0)
    case finalized(id: UUID, spans: [FinalSpeechSpan])
    case restarting(String)
}

nonisolated enum SpeechFailure: Error, LocalizedError {
    case permission(String)
    case unavailable(String)
    case modelRequired
    case ended

    var errorDescription: String? {
        switch self {
        case .permission(let message), .unavailable(let message): message
        case .modelRequired: "A speech model is needed for this language. Download it before starting."
        case .ended: "Speech recognition ended unexpectedly. Your position is saved; tap Resume to retry."
        }
    }
}

@MainActor
protocol SpeechSource: AnyObject {
    func run(locale: Locale, downloadModels: Bool,
             event: @escaping @MainActor @Sendable (SpeechEvent) -> Void) async throws
    func stop()
}
