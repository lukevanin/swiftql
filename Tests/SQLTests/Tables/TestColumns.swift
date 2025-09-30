//
//  TestColumns.swift
//  
//
//  Created by Luke Van In on 2023/08/02.
//

import Foundation
import SwiftQL


 @SQLResult
 struct TestColumns {
 
     let id: String
 
     let value: Int?
 }


@SQLResult
struct FamilyMemberParent: Equatable {
    
    let name: String?
    
    let parent: String?
}
