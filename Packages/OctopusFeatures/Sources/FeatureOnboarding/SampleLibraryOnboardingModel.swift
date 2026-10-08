import Foundation
import Combine
import OctopusDomain
import OctopusDesignSystem

/// Örnek içerik ancak açık bir seçimle kurulur; çift dokunma tek kuruluma gider.
@MainActor
final class SampleLibraryOnboardingModel: ObservableObject {
    enum State: Equatable { case idle, installing, installed }

    @Published private(set) var state: State = .idle
    @Published private(set) var errorMessage: String?
    private let installer: @MainActor () async throws -> Void

    init(install: @escaping @MainActor () async throws -> Void) {
        installer = install
    }

    @discardableResult
    func install() async -> Bool {
        guard state == .idle else { return false }
        state = .installing
        errorMessage = nil
        do {
            try Task.checkCancellation()
            try await installer()
            try Task.checkCancellation()
            state = .installed
            return true
        } catch is CancellationError {
            state = .idle
            return false
        } catch {
            errorMessage = (error as? AppError)?.userMessage
                ?? "Örnek kütüphane hazırlanamadı. Tekrar dene."
            state = .idle
            return false
        }
    }
}
