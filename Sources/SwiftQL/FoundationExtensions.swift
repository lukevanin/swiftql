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


extension UUID {
    
    ///
    /// Initializes a UUID with a Data object.
    ///
    init(data: Data) {
        self = data.withUnsafeBytes { (p: UnsafeRawBufferPointer) -> UUID in
            let b = p.bindMemory(to: uuid_t.self)
            return UUID(uuid: b[0])
        }
    }

    ///
    /// Creates a Data object from the UUID.
    ///
    func data() -> Data {
        withUnsafePointer(to: self) {
            Data(bytes: $0, count: MemoryLayout.size(ofValue: self))
        }
    }
}
