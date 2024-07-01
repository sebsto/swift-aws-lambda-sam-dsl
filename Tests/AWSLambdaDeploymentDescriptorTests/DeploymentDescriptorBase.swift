// ===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftAWSLambdaRuntime open source project
//
// Copyright (c) 2017-2023 Apple Inc. and the SwiftAWSLambdaRuntime project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftAWSLambdaRuntime project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

@testable import AWSLambdaDeploymentDescriptor
import XCTest
import Yams

class DeploymentDescriptorBaseTest: XCTestCase {
    var codeURI: String! = nil
    let fileManager = FileManager.default
    let functionName = MockDeploymentDescriptorBuilder.functionName

    override func setUpWithError() throws {
        // create a fake lambda package zip file
        let (_, tempFile) = try self.prepareTemporaryPackageFile()
        self.codeURI = tempFile
    }

    override func tearDownWithError() throws {
        // delete the fake lambda package (silently ignore errors)
        self.deleteTemporaryPackageFile(self.codeURI)
        self.codeURI = nil
    }

    @discardableResult
    func prepareTemporaryPackageFile() throws -> (String, String) {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
        let packageDir = MockDeploymentDescriptorBuilder.packageDir()
        let packageZip = MockDeploymentDescriptorBuilder.packageZip()
        try fm.createDirectory(atPath: tempDir.path + packageDir,
                               withIntermediateDirectories: true)
        let tempFile = tempDir.path + packageDir + packageZip
        XCTAssertTrue(fm.createFile(atPath: tempFile, contents: nil))
        return (tempDir.path, tempFile)
    }

    func deleteTemporaryPackageFile(_ file: String) {
        let fm = FileManager.default
        try? fm.removeItem(atPath: file)
    }

    // expected YAML values are either
    // <indent>Key:
    // <indent>Key: Value
    // <indent>- Value
    enum Expected {
        case keyOnly(indent: Int, key: String)
        case keyValue(indent: Int, keyValue: [String: String])
        case arrayKey(indent: Int, key: String? = nil, value: String? = nil)
//        case arrayKeyValue(indent: Int, key: [String:String])
        func string() -> [String] {
            let indent = 2 // default indent for Yams encoder
            var value: [String] = []
            switch self {
            case .keyOnly(let i, let k):
                value = [String(repeating: " ", count: indent * i) + "\(k):"]
            case .keyValue(let i, let kv):
                value = kv.keys.map { String(repeating: " ", count: indent * i) + "\($0): \(kv[$0] ?? "")" }
            case .arrayKey(let i, let k, let v):
                value = [String(repeating: " ", count: indent * i) + "- \(k ?? "")\(v == nil ? "" : ": \(v!)")"]
//            case .arrayKeyValue(let i, let kv):
//                value = kv.keys.map { "- \($0): \(String(describing: kv[$0]))" }.joined(separator: "\n")
            }
            return value
        }
    }

    private func testDeploymentDescriptor(deployment: String,
                                          expected: [Expected]) -> Bool {
        // given
        let samYAML = deployment

        // then
        let result = expected.allSatisfy {
            // each string in the expected [] is present in the YAML
            var result = true
            for item in $0.string() {
                result = result && samYAML.contains(item)
            }
            return result
        }

        if !result {
            print("===========")
            print(samYAML)
            print("-----------")
            print(expected.compactMap { $0.string().joined(separator: "\n") }.joined(separator: "\n"))
            print("===========")
        }

        return result
    }

    func generateAndTestDeploymentDescriptor<T: MockDeploymentDescriptorBehavior>(deployment: T,
                                                                                  expected: [Expected]) -> Bool {
        // when
        let samYAML = deployment.toYAML()

        return self.testDeploymentDescriptor(deployment: samYAML, expected: expected)
    }

    func generateAndTestDeploymentDescriptor<T: MockDeploymentDescriptorBehavior>(deployment: T,
                                                                                  expected: Expected) -> Bool {
        self.generateAndTestDeploymentDescriptor(deployment: deployment, expected: [expected])
    }

    func expectedSAMHeaders() -> [Expected] {
        [Expected.keyValue(indent: 0,
                           keyValue: [
                               "Description": "A SAM template to deploy a Swift Lambda function",
                               "AWSTemplateFormatVersion": "'2010-09-09'",
                               "Transform": "AWS::Serverless-2016-10-31",
                           ])]
    }

    func expectedFunction(architecture: String = "arm64") -> [Expected] {
        [
            Expected.keyOnly(indent: 0, key: "Resources"),
            Expected.keyOnly(indent: 1, key: "TestLambda"),
            Expected.keyValue(indent: 2, keyValue: ["Type": "AWS::Serverless::Function"]),
            Expected.keyOnly(indent: 2, key: "Properties"),
            Expected.keyValue(indent: 3, keyValue: [
                "Handler": "Provided",
                "CodeUri": self.codeURI,
                "Runtime": "provided.al2",
            ]),
            Expected.keyOnly(indent: 3, key: "Architectures"),
            Expected.arrayKey(indent: 3, key: architecture),
        ]
    }

    func expectedEnvironmentVariables() -> [Expected] {
        [
            Expected.keyOnly(indent: 3, key: "Environment"),
            Expected.keyOnly(indent: 4, key: "Variables"),
            Expected.keyValue(indent: 5, keyValue: ["NAME1": "VALUE1"]),
        ]
    }

    func expectedHttpAPi() -> [Expected] {
        [
            Expected.keyOnly(indent: 3, key: "Events"),
            Expected.keyOnly(indent: 4, key: "HttpApiEvent"),
            Expected.keyValue(indent: 5, keyValue: ["Type": "HttpApi"]),
        ]
    }

    func expectedQueue() -> [Expected] {
        [
            Expected.keyOnly(indent: 0, key: "Resources"),
            Expected.keyOnly(indent: 1, key: "QueueTestQueue"),
            Expected.keyValue(indent: 2, keyValue: ["Type": "AWS::SQS::Queue"]),
            Expected.keyOnly(indent: 2, key: "Properties"),
            Expected.keyValue(indent: 3, keyValue: ["QueueName": "test-queue"]),
        ]
    }

    func expectedQueueEventSource(source: String) -> [Expected] {
        [
            Expected.keyOnly(indent: 3, key: "Events"),
            Expected.keyOnly(indent: 4, key: "SQSEvent"),
            Expected.keyValue(indent: 5, keyValue: ["Type": "SQS"]),
            Expected.keyOnly(indent: 5, key: "Properties"),
            Expected.keyValue(indent: 6, keyValue: ["Enabled": "true",
                                                    "BatchSize": "10"]),
            Expected.keyOnly(indent: 6, key: "Queue"),
            Expected.keyOnly(indent: 7, key: "Fn::GetAtt"),
            Expected.arrayKey(indent: 7, key: source),
            Expected.arrayKey(indent: 7, key: "Arn"),
        ]
    }

    func expectedQueueEventSource(arn: String) -> [Expected] {
        [
            Expected.keyOnly(indent: 3, key: "Events"),
            Expected.keyOnly(indent: 4, key: "SQSEvent"),
            Expected.keyValue(indent: 5, keyValue: ["Type": "SQS"]),
            Expected.keyOnly(indent: 5, key: "Properties"),
            Expected.keyValue(indent: 6, keyValue: ["Enabled": "true",
                                                    "BatchSize": "10",
                                                    "Queue": arn]),
        ]
    }
}
