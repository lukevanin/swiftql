import Foundation
import SwiftQL

// Issue #789: the same query body type-checks against SQLite and against a
// second dialect. The dialect is named once, where the query begins. Swift
// values, optionals, and named bindings are expressions of every dialect, so
// they are operands next to a column of either. SQLite's own operations apply
// to a SQLite column, to a composed SQLite expression, and to a value.
// Compiled with Support/DialectParameterisedSupport.swift,
// Support/DialectTypeParameterSupport.swift, and the second dialect's
// generated surface in Support/Generated/CompileFailSecondDialect.

func sqliteQuery(name: String, minimumAge: Int) -> any XLQueryStatement<DialectPerson> {
    sql { schema in
        let person = schema.table(DialectPerson.self)
        Select(person)
        From(person)
        Where(
            person.name == name
                && person.age >= minimumAge
                && (person.nickname.isNull() || person.nickname == "x")
                && person.name.like("a%")
                && (person.name + person.name).collate(.nocase) == name
                && person.name.collate(.nocase) == "abc"
                && "abc".collate(.nocase) == person.name
                && person.age.in([1, 2, 3])
                && switchCase(person.age).when(1, then: "one").else("other") == name
        )
        OrderBy(person.age.descending())
        Limit(10)
    }
}

func secondDialectQuery(name: String, minimumAge: Int) -> any XLQueryStatement<SecondDialectPerson> {
    sql(dialect: CompileFailSecondDialect.self) { schema in
        let person = schema.table(SecondDialectPerson.self)
        Select(person)
        From(person)
        Where(
            person.name == name
                && person.age >= minimumAge
                && (person.nickname.isNull() || person.nickname == "x")
                && person.name.like("a%")
                && person.age.in([1, 2, 3])
                && switchCase(person.age).when(1, then: "one").else("other") == name
        )
        OrderBy(person.age.descending())
        Limit(10)
    }
}

/// A helper that composes part of a query takes and returns its dialect's
/// expression protocol.
func adults(_ age: any XLSQLiteExpression<Int>) -> some XLSQLiteExpression<Bool> {
    age >= 18
}

func secondDialectAdults(
    _ age: any CompileFailSecondDialectExpression<Int>
) -> some CompileFailSecondDialectExpression<Bool> {
    age >= 18
}

func helpers() {
    let sqlite = XLSchema().table(DialectPerson.self)
    let second = XLSchema(dialect: CompileFailSecondDialect.self).table(SecondDialectPerson.self)
    _ = adults(sqlite.age) && sqlite.name == "a"
    _ = secondDialectAdults(second.age) && second.name == "a"
    let binding = XLNamedBindingReference<Int>(name: "age")
    _ = sqlite.age == binding
    _ = second.age == binding
    _ = adults(binding)
    _ = secondDialectAdults(binding)
}
