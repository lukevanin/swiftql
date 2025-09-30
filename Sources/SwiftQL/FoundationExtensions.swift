//
//  FoundationExtensions.swift
//
//
//  Created by Luke Van In on 2023/07/21.
//

import Foundation


extension Data {
    func hex() -> String {
        map {
            String(format: "%02x", $0)
        }
        .joined()
    }
}


extension UUID {
        
    init(data: Data) {
        self = data.withUnsafeBytes { (p: UnsafeRawBufferPointer) -> UUID in
            let b = p.bindMemory(to: uuid_t.self)
            return UUID(uuid: b[0])
        }
    }

    func data() -> Data {
        withUnsafePointer(to: self) {
            Data(bytes: $0, count: MemoryLayout.size(ofValue: self))
        }
    }
}
