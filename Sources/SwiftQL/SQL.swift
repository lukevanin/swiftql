// The Swift Programming Language
// https://docs.swift.org/swift-book

//@attached(
//    extension,
//    conformances: 
//        SQLResult,
//        SQLTable,
//    names:
////        named(Nullable),
////        named(MetaResult),
////        named(MetaNullableResult),
////        named(MetaCommonTable),
////        named(SQLReader),
//        arbitrary
//)
@attached(member, names: arbitrary)
@attached(extension, conformances: XLResult, XLTable, names: arbitrary)
public macro SQLTable(name: String? = nil) = #externalMacro(module: "SQLMacros", type: "SQLTableMacro")

@attached(member, names: arbitrary)
@attached(extension, conformances: XLResult, names: arbitrary)
public macro SQLResult() = #externalMacro(module: "SQLMacros", type: "SQLResultMacro")
