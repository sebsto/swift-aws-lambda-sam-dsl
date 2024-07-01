// swift-tools-version:5.10

import PackageDescription

let package = Package(
    name: "swift-aws-lambda-sam-dsl",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        // SwiftPM plugin to deploy a SAM Lambda function
        .plugin(name: "AWSLambdaDeployer", targets: ["AWSLambdaDeployer"]),

        // Shared Library to generate a SAM deployment descriptor
        .library(name: "AWSLambdaDeploymentDescriptor", type: .dynamic, targets: ["AWSLambdaDeploymentDescriptor"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", branch: "main"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.2"),
    ],
    targets: [
        .target(
            name: "AWSLambdaDeploymentDescriptor",
            dependencies: [.product(name: "Yams", package: "Yams")],
            path: "Sources/AWSLambdaDeploymentDescriptor",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency=complete")]
        ),

        // JSON Schema Generator
        .executableTarget(
            name: "AWSLambdaDeploymentDescriptorGenerator",
            dependencies: [
                .target(name: "AWSLambdaDeploymentDescriptor"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
            ],
            path: "Sources/AWSLambdaDeploymentDescriptorGenerator",
            exclude: ["Generated", "Resources"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency=complete")]
        ),

        .plugin(
            name: "AWSLambdaDeployer",
            capability: .command(
                intent: .custom(
                    verb: "deploy",
                    description: "Deploy the Lambda ZIP created by the archive plugin. Generates SAM-compliant deployment files based on deployment struct passed by the developer and invoke the SAM command."
                )
//                permissions: [.writeToPackageDirectory(reason: "This plugin generates a SAM template to describe your deployment")]
            )
        ),
        .testTarget(
            name: "AWSLambdaDeploymentDescriptorTests",
            dependencies: [
                .byName(name: "AWSLambdaDeploymentDescriptor"),
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency=complete")]
        ),

        // test the SAM JSON Schema reader
        .testTarget(
            name: "AWSLambdaDeploymentDescriptorGeneratorTests",
            dependencies: [
                .byName(name: "AWSLambdaDeploymentDescriptorGenerator"),
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency=complete")]
        ),
    ]
)
