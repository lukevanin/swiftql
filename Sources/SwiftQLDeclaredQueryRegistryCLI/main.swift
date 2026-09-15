//
//  main.swift
//  swiftql-declared-query-registry
//
//  Issue #659: the tool SwiftQLDeclaredQueryRegistryPlugin runs. It scans a
//  target's Swift sources for @SQLQuery and @SQLQueries declarations and
//  writes the target's declared-query registry.
//
//  usage: swiftql-declared-query-registry --target-name NAME --output PATH FILE...
//

import Foundation
import SwiftQLDeclaredQueryDiscovery


func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(64)
}

let arguments = Array(CommandLine.arguments.dropFirst())
var targetName: String?
var outputPath: String?
var files: [String] = []
var index = 0
while index < arguments.count {
    switch arguments[index] {
    case "--target-name":
        index += 1
        guard index < arguments.count else {
            fail("--target-name needs a value")
        }
        targetName = arguments[index]
    case "--output":
        index += 1
        guard index < arguments.count else {
            fail("--output needs a value")
        }
        outputPath = arguments[index]
    default:
        files.append(arguments[index])
    }
    index += 1
}

guard let targetName, let outputPath else {
    fail("usage: swiftql-declared-query-registry --target-name NAME --output PATH FILE...")
}

var scan = DeclaredQueryScan()
for file in files.sorted() {
    let source: String
    do {
        source = try String(contentsOfFile: file, encoding: .utf8)
    }
    catch {
        fail("cannot read \(file): \(error.localizedDescription)")
    }
    scan.merge(DeclaredQueryScanner.scan(source: source, file: file))
}

for skipped in scan.skipped {
    FileHandle.standardError.write(Data("\(skipped.file):\(skipped.line): warning: \(skipped.reason)\n".utf8))
}

let rendered = DeclaredQueryRegistryRenderer.render(targetName: targetName, scan: scan)
let outputURL = URL(fileURLWithPath: outputPath)
// Rewriting identical content would still touch the file and recompile the
// target, so an unchanged registry is left alone.
if (try? String(contentsOf: outputURL, encoding: .utf8)) != rendered {
    do {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try rendered.write(to: outputURL, atomically: true, encoding: .utf8)
    }
    catch {
        fail("cannot write \(outputPath): \(error.localizedDescription)")
    }
}
