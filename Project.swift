import ProjectDescription

let project = Project(
    name: "ImageTools",
    targets: [
        .target(
            name: "ImageTools",
            destinations: .macOS,
            product: .app,
            bundleId: "net.kishonti.ImageTools",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(
                with: [
                    "CFBundleName": "ImageTools",
                    "CFBundleDisplayName": "ImageTools",
                    "CFBundleIconName": "AppIcon",
                    "LSMinimumSystemVersion": "14.0",
                    "NSHumanReadableCopyright": "",
                ]
            ),
            sources: ["Sources/**"],
            resources: ["Resources/**"],
            dependencies: [],
            settings: .settings(
                base: ["ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon"]
            )
        ),
    ]
)
