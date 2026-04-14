import ProjectDescription

let defaultDeploymentTarget: DeploymentTargets = .macOS("13.0")
let signingTeam = Environment.teamId.getString(default: "3VDQ4656LX")
let marketingVersion = "1.0.0"
let buildNumber = "1"

func targetSettings() -> Settings {
    var base = SettingsDictionary()
        .automaticCodeSigning(devTeam: signingTeam)
    base["COMPILATION_CACHE_ENABLE_CACHING"] = .string("NO")
    base["COMPILATION_CACHE_ENABLE_PLUGIN"] = .string("NO")
    base["MARKETING_VERSION"] = .string(marketingVersion)
    base["CURRENT_PROJECT_VERSION"] = .string(buildNumber)
    return .settings(base: base)
}

let project = Project(
    name: "Shorty",
    organizationName: "Peyton Randolph",
    settings: targetSettings(),
    targets: [
        .target(
            name: "ShortyCore",
            destinations: .macOS,
            product: .framework,
            bundleId: "app.peyton.shorty.core",
            deploymentTargets: defaultDeploymentTarget,
            infoPlist: .default,
            sources: [
                "Sources/ShortyCore/**"
            ],
            resources: [
                "Sources/ShortyCore/Resources/**"
            ],
            settings: targetSettings()
        ),
        .target(
            name: "Shorty",
            destinations: .macOS,
            product: .app,
            bundleId: "app.peyton.shorty",
            deploymentTargets: defaultDeploymentTarget,
            infoPlist: .file(path: "Info.plist"),
            sources: [
                "Sources/Shorty/**"
            ],
            dependencies: [
                .target(name: "ShortyCore")
            ],
            settings: targetSettings()
        ),
        .target(
            name: "ShortyBridge",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "app.peyton.shorty.bridge",
            deploymentTargets: defaultDeploymentTarget,
            infoPlist: .default,
            sources: [
                "Sources/ShortyBridge/**"
            ],
            dependencies: [
                .target(name: "ShortyCore")
            ],
            settings: targetSettings()
        ),
        .target(
            name: "ShortyScreenshots",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "app.peyton.shorty.screenshots",
            deploymentTargets: defaultDeploymentTarget,
            infoPlist: .default,
            sources: [
                "Sources/ShortyScreenshots/**",
                "Sources/Shorty/SettingsView.swift",
                "Sources/Shorty/StatusBarView.swift"
            ],
            dependencies: [
                .target(name: "ShortyCore")
            ],
            settings: targetSettings()
        ),
        .target(
            name: "ShortyCoreTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "app.peyton.shorty.ShortyCoreTests",
            deploymentTargets: defaultDeploymentTarget,
            infoPlist: .default,
            sources: [
                "Tests/ShortyCoreTests/**"
            ],
            dependencies: [
                .target(name: "ShortyCore")
            ],
            settings: targetSettings()
        )
    ]
)
