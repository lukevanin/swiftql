# SwiftQL

Swift Query Language allows you to write type-safe relational database queries using familiar Swift syntax. 

The primary goal of SwiftQL is to allow SQL queries to be written in a type-safe manner, so that SQL queries can be verified at compile time, to reduce runtime errors and security issues caused by common mistakes such as incorrect syntax, or improperly escaped input.

SwiftQL uses SQLite and as such attempts to adhere to SQL as understood by SQLite within reason. 

SwiftQL is currently only a proof of concept and is not ready for use in production systems. 

If you are intereted in using SwiftQL in your project please consider contributing or donating.

## Tutorial

SwiftQL works with relational databases. Objects in SwiftQL are derived from _tables_.   

To use an object in SwiftQL, you first need to define meta-data which describes how each object is stored in the database.

At present this definition needs to be implemented by hand. 

A future goal of SwiftQL is to derive the schema automatically from Swift objects.

First define the types you would like to use in your database. 

Value types are recommended, although reference types can also be used. 

SwiftQL currently does not support enums or protocols.
 
```
struct Sample: Identifiable, Equatable {
    
    let id: String
    let value: Int
}
```

Next we create a custom class conforming to the `Database` protocol, which describes the schema or layout of the database.

Implement the `Schema` associated type, which extends from the `DatabaseSchema`.
 

```
class MyDatabase: Database {
    final class Schema: DatabaseSchema {
```

Within the schema class we need to define a class which describes the schema for each table in the database. In this example we define a schema for the `Samples` table.

We need to define a property on the class for each field in the table. Our Sample table has an `id` primary key field which is a string, and `value` field which is an integer. 

SwiftQL supports the following types for fields:

`Boolean`: Stored as 64-bit integer, where `false` is stored as `0` and `true` is stored as `1`. 
`Int`: Stored as 64-bit integer.
`Double`: Stored as IEEE double precision floating point.
`String`: Stored as UTF-8 encoded null terminated string.
`Data`: Stored as raw bytes.
`URL`: Stored as text using the `.absoluteString` representation.
`UUID`: Stored as text using the `.uuidString` representation.
`Date`: Stored as text using `ISO8601` representation

Each field requires the name of the column in the table. 

We also need to define the `tableName` which is the name used in SQL queries.

`tableFields` should return an array containing all of the fields for the table. This is used by SwiftQL to process some queries, such as table `create` statements.

The `entity(from:)` method should return an instance of the entity stored in the table, deserialized from the `SQLRow` provided in the parameter. This method is used by SwiftQL to instantiate the entity when returning a result from a select query. 
 
Finally, the `values(entity:)` method should return a dictionary that represents an instance of the Swift entity in a form that is understood by SQL.  

```
        final class SampleSchema: BaseTableSchema, TableSchema {
        
            lazy var id = PrimaryKeyField<String>(name: "id", table: self)
            lazy var value = Field<Int>(name: "value", table: self)
            
            static let tableName = SQLIdentifier(stringLiteral: "samples")

            var tableFields: [AnyField] {
                return [id, value]
            }
            
            func entity(from row: SQLRow) -> Sample {
                Sample(
                    id: row.field(id),
                    value: row.field(value)
                )
            }
            
            func values(entity: Sample) -> [SQLIdentifier : SQLExpression] {
                [
                    id.name: StringLiteral(entity.id),
                    value.name: IntegerLiteral(entity.value)
                ]
            }
        }
```

Lastly we need to provide a variable to access the schema, and a constructor to instantiate the database.
 
```

        func samples() -> SampleSchema {
            schema(table: SampleSchema.self)
        }
    }
    
    let connection: SQLite.Connection
    
    init(connection: SQLite.Connection) {
        self.connection = connection
    }
}
}
```

Once we have the database definition in place we can instantiate the database and start to use it. The code below opens the database file named `mydatabase.sqlite3` in the cache directory. 

```
let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
let fileURL = directory.appendingPathComponent("mydatabase").appendingPathExtension("sqlite3")
let resource = SQLite.Resource(fileURL: fileURL)
let connection = try resource.connect()
let database = MyDatabase(connection: connection)
```

Create each table:

```
try database.execute { db in
    // CREATE TABLE IF NOT EXISTS `samples`
    // `id` TEXT PRIMARY KEY NOT NULL,
    // `value` INT NOT NULL
    Create(db.samples())
}
```

Insert data into the database:

```
try database.execute { db in
    // INSERT INTO `samples`
    // ( `id`, `value` )
    // VALUES ( ?1, ?2 )"
    let sample = db.samples()
    Insert(sample, Sample(id: "foo", value: 7))
}
```

Fetch data from the database

```
try database.execute { db in
    // SELECT `t0`.`id`, `t0`.`value`
    // FROM `samples` AS `t0`
    let sample = db.samples()
    Select(sample)
    From(sample)
}
```

Note in the above examples that we used a variable `sample` to refer to the schema. This is used when we need to refer to the same table multiple times in a query. In queries where a table is used only once, such as in the `insert` example, the table instance can be used directly without assigning it to a variable. 

## TODO:

Below are some of the goals for SwiftQL, roughly in order of highest priority first.

- Create table if it does not exist when it is accessed?
- SQL GROUP BY syntax.  
- Handle SQLITE_BUSY errors.
- Allow only read (select) statements to be observed. 
- Optimize observable statements: Only re-query when the tables and fields mentioned in the query are changed.
- Bulk import from CSV and data frames.
- Automatic schema migration when opening a populated database which has an outdated schema.
- Migrate documentation to Swift-DocC.
- Interface to other databases including Postgres and MySQL.

## License:

SwiftQL is free for commercial and non-commercial use. 

Attribution to the original source is required. 
