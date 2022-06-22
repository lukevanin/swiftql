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


extension Array {
    func appending(_ element: Element) -> Array {
        var output = self
        output.append(element)
        return output
    }
    
    func appending(contentsOf elements: Array) -> Array {
        var output = self
        output.append(contentsOf: elements)
        return output
    }
}
