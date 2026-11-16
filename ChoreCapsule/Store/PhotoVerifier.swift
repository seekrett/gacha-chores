import UIKit
import FoundationModels

/// Result of checking whether a proof photo matches its chore.
enum PhotoVerdict: Equatable, Sendable {
    case approved(observed: String)
    case rejected(observed: String, reason: String)
    /// This phone can't run the on-device check (no Apple Intelligence or older iOS).
    case unavailable(reason: String)
    /// The check is available but didn't finish. The user should retry.
    case failed(reason: String)
}

@available(iOS 26.0, *)
@Generable
struct PhotoJudgement {
    @Guide(description: "One short, literal sentence describing what is actually visible in the photo or photos.")
    var observed: String

    @Guide(description: "True only if the main object or area of the chore (for example the bed, the sink, the laundry, the bathroom) is clearly visible.")
    var choreSubjectVisible: Bool

    @Guide(description: "True only if the photos show the chore in a finished state. For before and after photos, the AFTER photo must show the same area clearly improved.")
    var looksFinished: Bool

    @Guide(description: "A short, friendly explanation for the user, under 20 words.")
    var reason: String
}

/// Checks proof photos with Apple's on-device Foundation Model. Photos never leave the phone.
enum PhotoVerifier {
    static let timeoutSeconds: Double = 45

    static let instructions = """
    You verify photo proof for a chore-tracking app. Be strict but fair.
    A photo passes only if it clearly shows the object or area of the chore, in a finished state.
    Fail photos of unrelated things, screenshots, blank or very dark images, or photos where the chore's main object is not visible.
    Judge only what is visible. Do not assume anything outside the frame.
    """

    static func prompt(title: String, notes: String, photoCount: Int) -> String {
        let details = notes.isEmpty ? "" : " Details: \(notes)"
        if photoCount >= 2 {
            return "Chore: \"\(title)\".\(details) The first image is the BEFORE photo and the second is the AFTER photo. Pass only if both show the same area related to this chore and the AFTER photo shows it done."
        }
        return "Chore: \"\(title)\".\(details) Is this photo believable proof that this chore was just completed?"
    }

    /// Whether the on-device check can run, with a human-readable explanation.
    static var status: (available: Bool, message: String) {
        guard #available(iOS 27.0, *) else {
            return (false, "AI photo checks need iOS 27 on an iPhone with Apple Intelligence.")
        }
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            if model.capabilities.contains(.vision) {
                return (true, "Photos are checked privately on this iPhone with Apple Intelligence.")
            }
            return (false, "This device's Apple Intelligence model can't read photos.")
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return (false, "This iPhone doesn't support Apple Intelligence, so photos can't be checked.")
            case .appleIntelligenceNotEnabled:
                return (false, "Turn on Apple Intelligence in the Settings app to enable photo checks.")
            case .modelNotReady:
                return (false, "Apple Intelligence is still downloading. Photo checks will work once it's ready.")
            @unknown default:
                return (false, "Apple Intelligence isn't available right now.")
            }
        }
    }

    static func verify(chore: Chore, images: [UIImage]) async -> PhotoVerdict {
        guard #available(iOS 27.0, *) else { return .unavailable(reason: status.message) }
        let current = status
        guard current.available else { return .unavailable(reason: current.message) }
        let cgImages = images.compactMap { $0.uprightCGImage(maxDimension: 1024) }
        guard !cgImages.isEmpty, cgImages.count == images.count else {
            return .failed(reason: "The photo couldn't be read. Try another one.")
        }
        do {
            return try await withTimeout(seconds: timeoutSeconds) {
                try await runModel(title: chore.title, notes: chore.notes, images: cgImages)
            }
        } catch {
            return .failed(reason: "The photo check didn't finish. Try again.")
        }
    }

    @available(iOS 27.0, *)
    private static func runModel(title: String, notes: String, images: [CGImage]) async throws -> PhotoVerdict {
        let session = LanguageModelSession(instructions: instructions)
        let text = prompt(title: title, notes: notes, photoCount: images.count)
        let judgement: PhotoJudgement
        if images.count >= 2 {
            judgement = try await session.respond(generating: PhotoJudgement.self) {
                text
                Attachment(images[0]).label("BEFORE photo")
                Attachment(images[1]).label("AFTER photo")
            }.content
        } else {
            judgement = try await session.respond(generating: PhotoJudgement.self) {
                text
                Attachment(images[0]).label("Proof photo")
            }.content
        }
        if judgement.choreSubjectVisible && judgement.looksFinished {
            return .approved(observed: judgement.observed)
        }
        return .rejected(observed: judgement.observed, reason: judgement.reason)
    }

    private static func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw CancellationError()
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            return result
        }
    }
}

extension UIImage {
    /// Redraws the image upright (orientation applied) and no larger than `maxDimension`.
    func uprightCGImage(maxDimension: CGFloat) -> CGImage? {
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxDimension / longest)
        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }.cgImage
    }
}
