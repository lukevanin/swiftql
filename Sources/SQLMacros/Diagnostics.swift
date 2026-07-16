//
//  Diagnostics.swift
//  SwiftQL
//

import SwiftDiagnostics
import SwiftSyntax


///
/// Diagnostic message emitted by the `SQLTable` and `SQLResult` macros when a declaration cannot be
/// mapped faithfully to SQL, such as a property whose type cannot be determined.
///
internal struct SQLMacroDiagnostic: DiagnosticMessage {

    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity

    init(id: String, message: String, severity: DiagnosticSeverity = .error) {
        self.message = message
        self.diagnosticID = MessageID(domain: "SQLMacros", id: id)
        self.severity = severity
    }
}


extension Diagnostic {

    ///
    /// Convenience initializer used to create an error diagnostic located at a given syntax node.
    ///
    init(node: some SyntaxProtocol, id: String, message: String) {
        self.init(node: Syntax(node), message: SQLMacroDiagnostic(id: id, message: message))
    }
}
