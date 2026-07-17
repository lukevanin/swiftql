import Foundation
import SwiftParser
import SwiftSyntax
import XCTest

final class SourceHygieneTests: XCTestCase {

    func testProductionSourcesDoNotContainCommentedOutDeclarations() throws {
        let sourceDirectory = packageRoot.appendingPathComponent("Sources", isDirectory: true)
        let sourceFiles = try swiftFiles(in: sourceDirectory)
        var offenders: [String] = []

        for sourceFile in sourceFiles {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            let syntax = Parser.parse(source: source)
            let relativePath = sourceFile.path.replacingOccurrences(
                of: packageRoot.path + "/",
                with: ""
            )

            for token in syntax.tokens(viewMode: .sourceAccurate) {
                inspect(token.leadingTrivia, in: relativePath, offenders: &offenders)
                inspect(token.trailingTrivia, in: relativePath, offenders: &offenders)
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            "Move disabled declarations into active code or delete them:\n\(offenders.joined(separator: "\n"))"
        )
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            XCTFail("Unable to enumerate production sources at \(directory.path)")
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
    }

    private func inspect(
        _ trivia: Trivia,
        in relativePath: String,
        offenders: inout [String]
    ) {
        for piece in trivia {
            guard case .lineComment(let comment) = piece,
                  isCommentedOutDeclaration(comment)
            else {
                continue
            }
            offenders.append("\(relativePath): \(comment)")
        }
    }

    private func isCommentedOutDeclaration(_ comment: String) -> Bool {
        let body = comment
            .dropFirst(2)
            .trimmingCharacters(in: .whitespaces)

        guard !body.hasPrefix("/"), !body.hasPrefix("!") else {
            return false
        }

        if body.hasPrefix("#if false") || body.hasPrefix("#if 0") {
            return true
        }

        var words = body.split {
            !$0.isLetter && !$0.isNumber && $0 != "_"
        }
        let modifiers: Set<Substring> = [
            "convenience", "distributed", "fileprivate", "final", "indirect", "infix",
            "internal", "isolated", "lazy", "mutating", "nonisolated", "nonmutating",
            "open", "optional", "override", "package", "postfix", "prefix", "private",
            "public", "required", "static", "unowned", "weak",
        ]
        while let first = words.first, modifiers.contains(first) {
            words.removeFirst()
        }

        let declarations: Set<Substring> = [
            "actor", "associatedtype", "class", "deinit", "enum", "extension", "func",
            "import", "init", "let", "macro", "operator", "precedencegroup", "protocol",
            "struct", "subscript", "typealias", "var",
        ]
        return words.first.map(declarations.contains) ?? false
    }
}
