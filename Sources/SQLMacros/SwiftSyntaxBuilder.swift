//
//  File.swift
//  
//
//  Created by Luke Van In on 2024/09/20.
//

import Foundation


#warning("TODO: Move SwiftSyntaxBuilder into separate reusable repository")
struct SwiftSyntaxBuilder {
    
    let indentation: String
    
    fileprivate var lines: [String] = []
    
    init(indentation: String = "  ") {
        self.indentation = indentation
    }
    
    private func indent(_ input: String) -> String {
        indentation + input
    }
    
    private mutating func appendLine(_ contents: String) {
        lines.append(indent(contents))
    }
    
    mutating func line(_ contents: String) {
        appendLine(contents)
    }
    
    mutating func block(_ prefix: String, opening: String = " {", closing: String = "}", contents: (inout SwiftSyntaxBuilder) -> Void) {
        var builder = SwiftSyntaxBuilder(indentation: indentation)
        contents(&builder)
        appendLine(prefix + opening)
        for line in builder.lines {
            appendLine(line)
        }
        appendLine(closing)
    }
    
    mutating func declaration(_ prefix: String, separator: String = ",", contents: (inout SwiftSyntaxListBuilder) -> Void) {
        block(prefix, opening: "(", closing: ")") { context in
            context.list(separator: separator, contents: contents)
        }
    }
    
    mutating func list(separator: String, contents: (inout SwiftSyntaxListBuilder) -> Void) {
        var builder = SwiftSyntaxListBuilder(separator: separator, builder: SwiftSyntaxBuilder(indentation: indentation))
        contents(&builder)
        for line in builder.lines {
            appendLine(line)
        }
    }
    
    func build() -> String {
        return lines.joined(separator: "\n")
    }
}


struct SwiftSyntaxListBuilder {
    
    let separator: String
    
    let builder: SwiftSyntaxBuilder
    
    fileprivate var lines: [String] = []
    
    mutating func item(contents: (inout SwiftSyntaxBuilder) -> Void) {
        var builder = self.builder
        contents(&builder)
        if !lines.isEmpty {
            var lastLine = lines.removeLast()
            lastLine.append(separator)
            lines.append(lastLine)
        }
        for line in builder.lines {
            lines.append(line)
        }
    }
}
