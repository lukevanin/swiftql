import Foundation
import SwiftQL

// Issue #789: the same query body type-checks against SQLite and against a
// second dialect. The dialect is named once, where the query begins. Swift
// values, optionals, and named bindings are universal, so they are operands
// next to a column of either dialect. SQLite's own operations apply to a
// SQLite column, to a composed SQLite expression, and to a value lifted into
// SQLite. Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.

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
                && "abc".sqlite.collate(.nocase) == person.name
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
        )
        OrderBy(person.age.descending())
        Limit(10)
    }
}

/// A helper that composes a predicate names its dialect; SQLite code writes
/// the shorthand.
func adults(_ person: DialectPerson.MetaNamedResult) -> any XLSQLiteExpression<Bool> {
    person.age >= 18
}

/// A helper generic over the dialect works for every model.
func named<Dialect>(
    _ name: any XLExpression<String, Dialect>,
    _ value: String
) -> some XLExpression<Bool, Dialect> {
    name == value
}

func helpers() {
    let sqlite = XLSchema().table(DialectPerson.self)
    let second = XLSchema(dialect: CompileFailSecondDialect.self).table(SecondDialectPerson.self)
    _ = adults(sqlite) && named(sqlite.name, "a")
    _ = named(second.name, "a")
    let binding = XLNamedBindingReference<Int>(name: "age")
    _ = sqlite.age == binding
    _ = second.age == binding
}
