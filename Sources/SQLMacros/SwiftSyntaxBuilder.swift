//
//  SwiftSyntaxBuilder.swift
//
//
//  Created by Luke Van In on 2024/09/20.
//

import Foundation


///
/// General purpose helper used to write Swift code. Used by SwiftQL macro builders for generating code for
/// table and result types annotated with the `SQLTable` and `SQLResult` macros.
///
internal struct SwiftSyntaxBuilder {
    
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
    
    ///
    /// Adds a line to the output.
    ///
    /// - Parameter contents: Literal code content.
    ///
    /// The `line` method is used to add a single line of output.
    ///
    /// Example: Declare a variable named "foo" with the value 42.
    /// ```swift
    /// var builder = SwiftSyntaxBuilder()
    /// builder.line("let foo = 12")
    /// ```
    ///
    mutating func line(_ contents: String) {
        appendLine(contents)
    }
    
    ///
    /// Adds an indented block of code to the output.
    ///
    /// - Parameter prefix: Code which appears before the block.
    /// - Parameter opening: Demarcating pair opening character. Should correspond to the closing character. Defaults to `'{'`.
    /// - Parameter closing: Demarcating pair closing character. Should correspond to the opening character. Defaults to `'}'`.
    /// - Parameter contents: Closure defining code contained in the block.
    ///
    /// The `block` method is used to add a structured block of code, such as a function definition or
    /// closure. The `contents` closure provides a `SwiftSyntaxBuilder` which is used to specify the contents of the code block.
    ///
    /// Example: Declare a function named "makeFoo" which returns an Int, in this case the number 42.
    ///
    /// ```swift
    /// var builder = SwiftSyntaxBuilder()
    /// builder.block("makeFoo() -> Int") { builder in
    ///     builder.line("return 42")
    /// }
    /// ```
    ///
    /// Example: Define a struct "Foo", with an attribute "name" of type Int.
    ///
    /// ```swift
    /// var builder = SwiftSyntaxBuilder()
    /// builder.block("Foo") { builder in
    ///     builder.line("var name: Int")
    /// }
    /// ```
    ///
    mutating func block(_ prefix: String, opening: String = " {", closing: String = "}", contents: (inout SwiftSyntaxBuilder) -> Void) {
        var builder = SwiftSyntaxBuilder(indentation: indentation)
        contents(&builder)
        appendLine(prefix + opening)
        for line in builder.lines {
            appendLine(line)
        }
        appendLine(closing)
    }
    
    ///
    /// Adds a declaration.
    ///
    /// - Parameter prefix: Code which appears first in the declaration, such as the name of a struct.
    /// - Parameter separator: Item delimiter. Defaults to `','`.
    /// - Parameter contents: Closure defining the items in the declaration.
    ///
    /// The `declaration` method is used to add a declaration such as an instance of a struct or class.
    /// The `contents` closure provides an instance of a `SwiftSyntaxListBuilder` which is
    /// used to define the parameters passed to the declaration.
    ///
    /// Example: Instantiate a struct named "Foo", setting the "name" attribute to the value 42:
    ///
    /// ```swift
    /// var builder = SwiftSyntaxBuilder()
    /// builder.declaration("Foo") { builder in
    ///     builder.item { builder in
    ///         builder.line("name: 42")
    ///     }
    /// }
    /// ```
    ///
    mutating func declaration(_ prefix: String, separator: String = ",", contents: (inout SwiftSyntaxListBuilder) -> Void) {
        block(prefix, opening: "(", closing: ")") { context in
            context.list(separator: separator, contents: contents)
        }
    }
    
    ///
    /// Adds a list of items to the output.
    ///
    /// - Parameter separator: List item delimiter.
    /// - Parameter contents: Closure defining the items in the list.
    ///
    mutating func list(separator: String, contents: (inout SwiftSyntaxListBuilder) -> Void) {
        var builder = SwiftSyntaxListBuilder(separator: separator, builder: SwiftSyntaxBuilder(indentation: indentation))
        contents(&builder)
        for line in builder.lines {
            appendLine(line)
        }
    }
    
    ///
    /// Outputs the accumulated contents.
    ///
    /// - Returns: Returns the lines added to the builder seperated by a newline `'\n'` character.
    ///
    func build() -> String {
        return lines.joined(separator: "\n")
    }
}


///
/// Specialised Swift code builder used to construct lists, such as arrays and parameters.
///
/// > Note: Use a relevant list method on `SwiftSyntaxBuilder` to obtain an instance of this object.
///
internal struct SwiftSyntaxListBuilder {
    
    ///
    /// Delimiter interposed between successive list items.
    ///
    let separator: String
    
    ///
    /// Parent `SwiftSyntaxBuilder` builder.
    ///
    let builder: SwiftSyntaxBuilder
    
    fileprivate var lines: [String] = []
    
    ///
    /// Adds an item to the list.
    ///
    /// - Parameter contents: Closure defining the contents of the list item.
    ///
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
