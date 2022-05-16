//
//  Extensions.swift
//  
//
//  Created by Luke Van In on 2022/05/16.
//

import Foundation

/// https://stackoverflow.com/a/62465044/762377
extension DataProtocol {
    func hexEncodedString(uppercase: Bool = false) -> String {
        return self.map {
            if $0 < 16 {
                return "0" + String($0, radix: 16, uppercase: uppercase)
            } else {
                return String($0, radix: 16, uppercase: uppercase)
            }
        }.joined()
    }
}
