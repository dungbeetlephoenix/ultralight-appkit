import Foundation
import Combine

extension Publisher where Failure == Never {
    // Keep the scheduling/subscription machinery out of each view's setup code.
    // Deferral is intentional: @Published emits before its stored value changes.
    @inline(never)
    func sinkOnMain(_ value: @escaping (Output) -> Void) -> AnyCancellable {
        receive(on: RunLoop.main).sink(receiveValue: value)
    }
}
