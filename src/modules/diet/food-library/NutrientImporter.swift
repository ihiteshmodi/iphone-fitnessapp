import Foundation

/// Applies nutrient values the owner approved (a CSV of name,key,amount) to the foods with those names.
/// Values not in the file are kept, so it can be applied again or in parts.
public final class NutrientImporter {
    public struct Result: Equatable {
        public let applied: Int
        public let missingFoods: [String]

        public init(applied: Int, missingFoods: [String]) {
            self.applied = applied
            self.missingFoods = missingFoods
        }
    }

    private let db: Database

    public init(_ db: Database) { self.db = db }

    public func apply(_ csv: String, overwriteExisting: Bool = true) throws -> Result {
        let library = FoodLibrary(db)
        var applied = 0
        var missing: [String] = []
        var changed: [Int: FoodDraft] = [:]
        for line in csv.split(whereSeparator: \.isNewline).dropFirst() {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 3 else { continue }
            let (name, key, amount) = (fields[0], fields[1], fields[2])
            guard let food = try library.food(named: name) else {
                if !missing.contains(name) { missing.append(name) }
                continue
            }
            var draft = changed[food.id] ?? food.draft
            var didChange = false
            if key == "omega3_form", let form = Omega3Form(rawValue: amount) {
                if overwriteExisting || draft.omega3Form == nil {
                    draft.omega3Form = form
                    didChange = true
                }
            } else if key == "glycemic_index", let gi = Double(amount), (0...115).contains(gi) {
                if overwriteExisting || draft.glycemicIndex == nil {
                    draft.glycemicIndex = gi
                    didChange = true
                }
            } else if let nutrient = Nutrient(rawValue: key), let value = Double(amount), value >= 0 {
                if overwriteExisting || draft.nutrients[nutrient] == nil {
                    draft.nutrients[nutrient] = value
                    didChange = true
                }
            } else {
                continue
            }
            if didChange {
                changed[food.id] = draft
                applied += 1
            }
        }
        if !changed.isEmpty {
            try db.transaction {
                for (id, draft) in changed { try library.update(id, draft) }
            }
        }
        return Result(applied: applied, missingFoods: missing)
    }
}
