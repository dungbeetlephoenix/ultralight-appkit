import Foundation
import Combine

@main struct BindingGates {
    static var failures = 0
    static var count = 0
    static var checks: [[String: Any]] = []
    static func check(_ name: String, _ pass: Bool) {
        count += 1
        checks.append(["name": name, "pass": pass])
        if !pass { failures += 1 }
        print("\(pass ? "PASS" : "FAIL") \(name)")
    }
    static func pump() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
    final class Model: ObservableObject { @Published var value = 0 }
    static func main() {
        do {
            let model = Model()
            var emissions: [Int] = []
            var stored: [Int] = []
            let token = model.$value.sinkOnMain { emissions.append($0); stored.append(model.value) }
            model.value = 1; model.value = 2
            check("Published values deferred past willSet", emissions.isEmpty)
            pump()
            check("Published initial and every burst value preserved", emissions == [0,1,2])
            check("Published storage fully updated at deferred delivery", stored == [2,2,2])
            token.cancel()
        }
        do {
            let subject = PassthroughSubject<Int,Never>()
            var values: [Int] = []
            let token = subject.sinkOnMain { values.append($0) }
            subject.send(1); subject.send(2)
            token.cancel(); pump()
            check("cancel drops pending values", values.isEmpty)
            subject.send(3); pump()
            check("cancel disconnects later emissions", values.isEmpty)
        }
        do {
            let subject = PassthroughSubject<Int,Never>()
            var values: [Int] = []
            var token: AnyCancellable?
            token = subject.sinkOnMain { values.append($0); token?.cancel() }
            subject.send(1); subject.send(2); pump()
            check("cancellation inside callback is safe and drops pending tail", values == [1])
        }
        do {
            let subject = PassthroughSubject<Int,Never>()
            var trace: [String] = []
            let token = subject.sinkOnMain { value in
                trace.append("begin\(value)")
                if value == 1 { subject.send(3); trace.append("sent3") }
                trace.append("end\(value)")
            }
            subject.send(1); subject.send(2); pump(); pump()
            check("nested emission remains deferred and ordered", trace == ["begin1","sent3","end1","begin2","end2","begin3","end3"])
            token.cancel()
        }
        do {
            let subject = PassthroughSubject<Int,Never>()
            var values: [Int] = []
            var onMain = true
            let token = subject.sinkOnMain { values.append($0); onMain = onMain && Thread.isMainThread }
            let finished = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                for value in 0..<100 { subject.send(value) }
                finished.signal()
            }
            _ = finished.wait(timeout: .now() + 2)
            check("background values are deferred", values.isEmpty)
            pump()
            check("background burst preserves all values in order", values == Array(0..<100))
            check("background emissions deliver on main thread", onMain)
            token.cancel()
        }
        do {
            let subject = PassthroughSubject<Int,Never>()
            var delivered = false
            let token = subject.sinkOnMain { _ in delivered = true }
            subject.send(1)
            let finished = DispatchSemaphore(value: 0)
            DispatchQueue.global().async { token.cancel(); finished.signal() }
            _ = finished.wait(timeout: .now() + 2)
            pump()
            check("background cancellation drops pending delivery", !delivered)
        }
        do {
            let subject = PassthroughSubject<Int,Never>()
            var values: [Int] = []
            let token = subject.sinkOnMain { values.append($0) }
            subject.send(1);subject.send(2);subject.send(completion: .finished)
            pump()
            check("completion does not discard preceding queued values", values == [1,2])
            token.cancel()
        }
        do {
            let subject = PassthroughSubject<Int,Never>()
            var values: [Int] = []
            let token = subject.sinkOnMain { values.append($0) }
            subject.send(1)
            _ = RunLoop.main.run(mode: RunLoop.Mode("NSEventTrackingRunLoopMode"), before: Date(timeIntervalSinceNow: 0.02))
            check("event-tracking mode does not run default-mode delivery", values.isEmpty)
            pump()
            check("default mode resumes queued delivery", values == [1])
            token.cancel()
        }
        let report: [String: Any] = ["passed": count - failures, "failed": failures, "checks": checks]
        if CommandLine.arguments.count > 1,
           let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("results.json"))
        }
        print("RESULT \(count-failures)/\(count)")
        exit(failures == 0 ? 0 : 1)
    }
}
