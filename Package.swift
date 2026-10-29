// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FitnessCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "FitnessCore", targets: ["FitnessCore"])
    ],
    targets: [
        .target(
            name: "FitnessCore",
            path: "src",
            resources: [.copy("shared/database/schema.sql")]
        ),
        .testTarget(
            name: "FitnessCoreTests",
            dependencies: ["FitnessCore"],
            path: "tests",
            exclude: [
                "data/import-export-database/import-export-database.feature",
                "diet/daily-diet/daily-diet.feature",
                "diet/diet-calories/diet-calories.feature",
                "diet/diet-plan/diet-plan.feature",
                "diet/food-library/food-library.feature",
                "diet/portions/portions.feature",
                "diet/supplement-cycles/supplement-cycles.feature",
                "logging/edit-sets/edit-sets.feature",
                "logging/edit-past-data/edit-past-data.feature",
                "logging/log-body-metrics/log-body-metrics.feature",
                "logging/log-sets/log-sets.feature",
                "nutrition/calorie-target/calorie-target.feature",
                "nutrition/daily-calories/daily-calories.feature",
                "nutrition/nutrition-settings/nutrition-settings.feature",
                "planning/deload-mode/deload-mode.feature",
                "planning/edit-plan/edit-plan.feature",
                "planning/exercise-detail/exercise-detail.feature",
                "planning/exercise-detail/pr-highlighting.feature",
                "planning/exercise-library/exercise-library.feature",
                "planning/muscle-anatomy/muscle-anatomy.feature",
                "planning/view-workout/view-workout.feature",
                "progress/measurement-progress/measurement-progress.feature",
                "progress/measurement-tolerance/measurement-tolerance.feature",
                "progress/muscle-volume/muscle-volume.feature",
                "settings/app-settings/app-settings.feature",
            ]
        ),
    ]
)
