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


// Issue #822: every clause and statement carries its dialect. The same
// statement shapes type-check in each dialect; a clause built from values
// alone takes the dialect of the query it is in, also in a module that sees
// both dialects' surfaces.

func sqliteStatements(name: String) {
    let sqlite = XLSchema()
    let person = sqlite.table(DialectPerson.self)
    let target = sqlite.into(DialectPerson.self)
    _ = sql { schema in
        let inner = schema.table(DialectPerson.self)
        let other = schema.nullableTable(DialectPerson.self)
        Select(inner)
        From(inner)
        Join.Left(other, on: other.id == inner.id)
        Where(true)
        GroupBy(inner.age)
        Having(inner.age > 1)
        OrderBy(inner.name.ascending(), Descending(expression: inner.age))
        Limit(10)
        Offset(5)
    }
    _ = sql { schema in
        let inner = schema.table(DialectPerson.self)
        Select(inner.age)
        From(inner)
        Where(inner.age == subqueryExpression { Select(1) })
        Union()
        Select(2)
    }
    _ = select(person).from(person).where(person.name == name).orderBy(person.age.ascending()).limit(1).offset(1)
    _ = select(person.age).from(person).union { select(1) }
    _ = delete(target).where(person.id == 1).returning(person)
    _ = QueryBuilder(select: person).from(person).and(person.age > 1).limit(5)
}

func secondDialectStatements(name: String) {
    let second = XLSchema(dialect: CompileFailSecondDialect.self)
    let person = second.table(SecondDialectPerson.self)
    let target = second.into(SecondDialectPerson.self)
    _ = sql(dialect: CompileFailSecondDialect.self) { schema in
        let inner = schema.table(SecondDialectPerson.self)
        let other = schema.nullableTable(SecondDialectPerson.self)
        Select(inner)
        From(inner)
        Join.Left(other, on: other.id == inner.id)
        Where(true)
        GroupBy(inner.age)
        Having(inner.age > 1)
        OrderBy(inner.name.ascending(), Descending(expression: inner.age))
        Limit(10)
        Offset(5)
    }
    _ = sql(dialect: CompileFailSecondDialect.self) { schema in
        let inner = schema.table(SecondDialectPerson.self)
        Select(inner.age)
        From(inner)
        Where(inner.age == schema.subqueryExpression { _ in Select(1) })
        Union()
        Select(2)
    }
    _ = sql(dialect: CompileFailSecondDialect.self) { schema in
        Delete(schema.into(SecondDialectPerson.self))
        Where(true)
    }
    _ = select(person).from(person).where(person.name == name).orderBy(person.age.ascending()).limit(1).offset(1)
    _ = delete(target).where(person.id == 1).returning(person)
    _ = XLDialectQueryBuilder(select: person).from(person).and(person.age > 1).limit(5)
}


// Issue #825: the macros' value slots take the model's dialect's expressions
// and Swift values, in a module that sees both surfaces.

func sqliteValueSlots(name: String, nickname: String?) {
    _ = sql { schema in
        let target = schema.into(DialectPerson.self)
        Update(target)
        Setting<DialectPerson> { row in
            row.name = name
            row.nickname = nickname
            row.age = target.age + 1
            row.id = 1
        }
    }
    _ = sql { schema in
        let target = schema.into(DialectPerson.self)
        Update(target)
        Setting(DialectPerson.MetaUpdate(name: target.name + "!", nickname: nil))
    }
    _ = DialectPerson.MetaInsert(id: 1, name: name, nickname: nickname, age: 2)
    let person = XLSchema().table(DialectPerson.self)
    _ = DialectPerson.columns(id: person.id + 1, name: person.name, nickname: person.nickname, age: 3)
    _ = #row(person.name + "!")
}

func secondDialectValueSlots(name: String, nickname: String?) {
    _ = sql(dialect: CompileFailSecondDialect.self) { schema in
        let target = schema.into(SecondDialectPerson.self)
        Update(target)
        Setting<SecondDialectPerson> { row in
            row.name = name
            row.nickname = nickname
            row.age = target.age + 1
            row.id = 1
        }
    }
    _ = sql(dialect: CompileFailSecondDialect.self) { schema in
        let target = schema.into(SecondDialectPerson.self)
        Update(target)
        Setting(SecondDialectPerson.MetaUpdate(name: target.name + "!", nickname: nil))
    }
    _ = SecondDialectPerson.MetaInsert(id: 1, name: name, nickname: nickname, age: 2)
    let person = XLSchema(dialect: CompileFailSecondDialect.self).table(SecondDialectPerson.self)
    _ = SecondDialectPerson.columns(id: person.id + 1, name: person.name, nickname: person.nickname, age: 3)
}


// Issue #828: a nullable column's slot is read as an optional-typed
// expression, which assigns back to itself, to another nullable column, and
// to a nullable value of the generated initializers, in every slot that takes
// a `Setting` closure. A non-nullable column's read assigns to a nullable
// column. The refusals of a read assigned where a value cannot be NULL are
// the `DialectSlotNullableRead*` fixtures.

func nullableSlotReads(nickname: String?) {
    _ = sql { schema in
        let target = schema.into(DialectPerson.self)
        Update(target)
        Setting<DialectPerson> { row in
            row.nickname = row.nickname
            row.nickname = target.nickname
            row.nickname = row.nickname
            row.name = target.name
            row.nickname = row.name
            let read: any XLSQLiteExpression<String?> = row.nickname
            row.nickname = read
            row.nickname = nickname
            row.nickname = nil
        }
    }
    let schema = XLSchema()
    let target = schema.into(DialectPerson.self)
    _ = update(target).set { row in
        row.nickname = row.nickname
    }
    let table = schema.table(DialectPerson.self)
    let excluded = schema.excluded(DialectPerson.self)
    _ = insert(table)
        .values(DialectPerson.MetaInsert(id: 1, name: "a", nickname: nickname, age: 2))
        .onConflict("id", doUpdate: { row in
            row.nickname = excluded.nickname
            row.nickname = row.nickname
        })
    let read = DialectPerson.MetaUpdate(nickname: target.nickname)
    _ = DialectPerson.MetaUpdate(nickname: read.nickname)
    _ = DialectPerson.MetaInsert(id: 1, name: "a", nickname: read.nickname, age: 2)
    _ = sql(dialect: CompileFailSecondDialect.self) { schema in
        let target = schema.into(SecondDialectPerson.self)
        Update(target)
        Setting<SecondDialectPerson> { row in
            row.nickname = target.nickname
            row.nickname = row.nickname
        }
    }
}


/// A custom function runs inside SQLite; the initializer `@SQLFunction`
/// generates takes SQLite expressions.
@SQLFunction(name: "whisper")
struct Whisper: XLCustomFunction {
    typealias T = String

    let text: any XLExpression<String>

    static func execute(reader: XLColumnReader) throws -> String {
        try reader.readText(at: 0).lowercased()
    }
}

func customFunction() {
    let person = XLSchema().table(DialectPerson.self)
    _ = Whisper(text: person.name) == "a"
    _ = Whisper(text: "A")
}


/// Generic code that names a model's common table passes it to `With`, which
/// checks the dialect of the common table's result.
func genericCommonTable<T>(_ type: T.Type, _ commonTable: T.MetaCommonTable) -> With<XLSQLiteDialect> where T: XLTable, T.XLModelDialect == XLSQLiteDialect {
    _ = with(commonTable)
    return With(commonTable)
}
