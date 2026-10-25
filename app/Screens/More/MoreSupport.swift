import FitnessCore
import Foundation

/// One place that turns a thrown error into the sentence shown in an alert.
enum MoreErrorText {
    static func message(for error: Error) -> String {
        (error as? ValidationError)?.message ?? error.localizedDescription
    }
}

/// Binds a view model to the services of the currently open database and to the session's change signal.
/// Models keep the latest services because importing a database replaces them.
struct MoreServiceLink {
    private(set) var services: Services?
    private var notify: () -> Void = {}

    mutating func bind(_ services: Services, notify: @escaping () -> Void) {
        self.services = services
        self.notify = notify
    }

    func didChange() { notify() }
}
