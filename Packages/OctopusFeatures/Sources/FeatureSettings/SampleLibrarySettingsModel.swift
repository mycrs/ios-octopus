import Foundation
import Combine
import OctopusDomain
import OctopusDesignSystem

@MainActor
final class SampleLibrarySettingsModel: ObservableObject {
    enum State: Equatable { case idle, installing, installed }

    @Published private(set) var state: State = .idle
    @Published private(set) var errorMessage: String?
    private let installer: @MainActor () async throws -> Void

    init(install: @escaping @MainActor () async throws -> Void) {
        installer = install
    }

    func install() async {
        guard state == .idle else { return }
        state = .installing
        errorMessage = nil
        do {
            try Task.checkCancellation()
            try await installer()
            try Task.checkCancellation()
            state = .installed
        } catch is CancellationError {
            state = .idle
        } catch {
            errorMessage = (error as? AppError)?.userMessage
                ?? "Örnek kütüphane hazırlanamadı. Tekrar dene."
            state = .idle
        }
    }
}
