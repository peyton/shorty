import ProjectDescription

let defaultDeploymentTarget: DeploymentTargets = .macOS("13.0")
let signingTeam = Environment.teamId.getString(default: "3VDQ4656LX")
let marketingVersion = "1.0.0"
let buildNumber = "1"

func targetSettings(includeAppAssets: Bool = false) -> Settings {
    var base = SettingsDictionary()
        .automaticCodeSigning(devTeam: signingTeam)
    if includeAppAssets {
        base["ASSETCATALOG_COMPILER_APPICON_NAME"] = .string("AppIcon")
        base["ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME"] = .string("AccentColor")
    }
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
            resources: [
                "Sources/Shorty/Resources/**"
            ],
            entitlements: "Shorty.entitlements",
            dependencies: [
                .target(name: "ShortyCore"),
                .target(name: "ShortySafariWebExtension")
            ],
            settings: targetSettings(includeAppAssets: true)
        ),
        .target(
            name: "ShortyAppStore",
            destinations: .macOS,
            product: .app,
            bundleId: "app.peyton.shorty.appstore",
            deploymentTargets: defaultDeploymentTarget,
            infoPlist: .file(path: "Info.plist"),
            sources: [
                "Sources/Shorty/**"
            ],
            resources: [
                "Sources/Shorty/Resources/**"
            ],
            entitlements: "ShortyAppStore.entitlements",
            dependencies: [
                .target(name: "ShortyCore"),
                .target(name: "ShortyAppStoreSafariWebExtension")
            ],
            settings: targetSettings(includeAppAssets: true)
        ),
        .target(
            name: "ShortySafariWebExtension",
            destinations: .macOS,
            product: .appExtension,
            bundleId: "app.peyton.shorty.SafariWebExtension",
            deploymentTargets: defaultDeploymentTarget,
            infoPlist: .file(path: "Sources/ShortySafariWebExtension/Info.plist"),
            sources: [
                "Sources/ShortySafariWebExtension/**"
            ],
            resources: [
                "Sources/ShortySafariWebExtension/Resources/**"
            ],
            entitlements: "ShortySafariWebExtension.entitlements",
            settings: targetSettings()
        ),
        .target(
            name: "ShortyAppStoreSafariWebExtension",
            destinations: .macOS,
            product: .appExtension,
            bundleId: "app.peyton.shorty.appstore.SafariWebExtension",
            deploymentTargets: defaultDeploymentTarget,
            infoPlist: .file(path: "Sources/ShortySafariWebExtension/Info.plist"),
            sources: [
                "Sources/ShortySafariWebExtension/**"
            ],
            resources: [
                "Sources/ShortySafariWebExtension/Resources/**"
            ],
            entitlements: "ShortySafariWebExtension.entitlements",
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
                "Sources/Shorty/ShortyBrand.swift",
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
