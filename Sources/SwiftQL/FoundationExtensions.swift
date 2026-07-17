//
//  FoundationExtensions.swift
//
//
//  Created by Luke Van In on 2023/07/21.
//

import Foundation


extension Data {
    
    ///
    /// Convenience function used to encode data into a hexadecimal string.
    ///
    internal func hex() -> String {
        map {
            String(format: "%02x", $0)
        }
        .joined()
    }
}
