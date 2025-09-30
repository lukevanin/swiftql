//
//  File.swift
//  
//
//  Created by Luke Van In on 2024/10/30.
//

import Foundation


extension Array {
    
    private enum InternalError: Error {
        case indexOutOfRange
    }
    
    func element(at index: Index) throws -> Element {
        guard index >= startIndex else {
            throw InternalError.indexOutOfRange
        }
        guard index <= endIndex else {
            throw InternalError.indexOutOfRange
        }
        return self[index]
    }
}


extension Date {
    
    init(string: String, format: String = "yyyy-MM-dd HH:mm") {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        self = formatter.date(from: string)!
    }
}
