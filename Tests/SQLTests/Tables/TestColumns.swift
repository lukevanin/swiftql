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


// Kept in a separate source file from its call-site regression test so the Swift 5.9
// ExtensionMacro static-member lookup bug cannot regress unnoticed.
@SQLResult
struct Swift59ColumnsLookupProjection: Equatable {

    let value: Int
}
