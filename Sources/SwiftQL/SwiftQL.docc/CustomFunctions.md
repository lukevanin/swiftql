# Custom Functions

Create custom functions that can be called from SQL expressions.

## Overview

SwiftQL allows custom functions to be installed on the database and called from
SQL expressions at runtime in a type-safe manner. This guide shows how to:

- Define a custom function.
- Install the function to make it available to the database engine.
- Call the function from an SQL statement.

For this example we will define a function that computes a distance from two
geographic coordinates defined by a latitude and longitude using the
[Haversine formula](https://en.wikipedia.org/wiki/Haversine_formula).

## Defining a function

To define a custom function, create a class or struct that conforms to the
`XLCustomFunction` protocol, and implement the `definition`, `makeSQL`, and
`execute` requirements. The initializer accepts expressions which are
passed to the function at runtime.

<!-- test: XLDocumentationTests.testDocumentationCustomFunctionRegistrationAndExecution -->
```swift
import Foundation
import SwiftQL

public struct HaversineDistance: XLCustomFunction {
    
    public typealias T = Double
    
    // Define the function signature. SQLite uses the name and number of 
    // parameters to differentiate functions.
    public static let definition = XLCustomFunctionDefinition(
        name: "haversineDistance",
        numberOfArguments: 4
    )
    
    // Define parameters which are passed to the function at runtime.
    private let fromLatitude: any XLExpression
    private let fromLongitude: any XLExpression
    private let toLatitude: any XLExpression
    private let toLongitude: any XLExpression
    
    init(
        fromLatitude: any XLExpression<Double>,
        fromLongitude: any XLExpression<Double>,
        toLatitude: any XLExpression<Double>,
        toLongitude: any XLExpression<Double>
    ) {
        self.fromLatitude = fromLatitude
        self.fromLongitude = fromLongitude
        self.toLatitude = toLatitude
        self.toLongitude = toLongitude
    }
    
    // Define how the function is formatted into an SQL expression.
    public func makeSQL(context: inout XLBuilder) {
        context.simpleFunction(name: Self.definition.name) { context in
            context.listItem(expression: fromLatitude.makeSQL)
            context.listItem(expression: fromLongitude.makeSQL)
            context.listItem(expression: toLatitude.makeSQL)
            context.listItem(expression: toLongitude.makeSQL)
        }
    }
    
    // Define the implementation details for how the function works. This is 
    // called at runtime from SQL, and the results are returned to SQL.
    public static func execute(reader: XLColumnReader) throws -> Double {
        let latA = try radians(degrees: reader.readReal(at: 0))
        let lonA = try radians(degrees: reader.readReal(at: 1))
        let latB = try radians(degrees: reader.readReal(at: 2))
        let lonB = try radians(degrees: reader.readReal(at: 3))
        let deltaLat = latB - latA
        let deltaLon = lonB - lonA
        let a = pow(sin(deltaLat / 2), 2)
            + cos(latA) * cos(latB) * pow(sin(deltaLon / 2), 2)
        return 2 * 6371 * asin(Swift.min(1, sqrt(a)))
    }
    
    // Helper method called by the function.
    private static func radians(degrees: Double) -> Double {
        (degrees / 180) * .pi
    }
}
```

## Installing the function

Once the function is defined it needs to be installed on the database. For GRDB 
this can be done by adding the function in the configuration, or by using the 
`GRDBDatabaseBuilder` provided by SwiftQL:

<!-- test: XLDocumentationTests.testDocumentationCustomFunctionRegistrationAndExecution -->
```swift
import Foundation
import GRDB
import SwiftQL

// Create the builder.
let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
let databaseURL = directory.appending(path: "my_database.sqlite")
let configuration = Configuration()
var builder = try GRDBDatabaseBuilder(
    url: databaseURL,
    configuration: configuration,
    logger: nil
)

// Add the custom function defined above.
builder.addFunction(HaversineDistance.self)

// Instantiate the database.
let database = try builder.build()
```

## Calling the function

The function can be used in any expression of the same type.

As an example we can compute the distance from a location to all restaurants 
using our new function.

First we define the restaurant:

<!-- test: XLDocumentationTests.testDocumentationCustomFunctionRegistrationAndExecution -->
```swift
@SQLTable struct Restaurant {
    let name: String
    let latitude: Double
    let longitude: Double
}
```

Next we define the result set that returns the name of each restaurant along 
with the distance to it.

<!-- test: XLDocumentationTests.testDocumentationCustomFunctionRegistrationAndExecution -->
```swift
@SQLResult struct NearbyRestaurant {
    let name: String
    let distance: Double
}
```

<!-- test: XLDocumentationTests.testDocumentationCustomFunctionRegistrationAndExecution -->
```swift
let myLatitude = XLNamedBindingReference<Double>(name: "myLatitude")
let myLongitude = XLNamedBindingReference<Double>(name: "myLongitude")
let query = sqlQuery { schema in
    let restaurant = schema.table(Restaurant.self)
    let result = NearbyRestaurant.columns(
        name: restaurant.name,
        distance: HaversineDistance(
            fromLatitude: myLatitude,
            fromLongitude: myLongitude,
            toLatitude: restaurant.latitude,
            toLongitude: restaurant.longitude
        ).rounded(to: 2)
    )
    return select(result)
        .from(restaurant)
        .orderBy(result.distance.ascending())
}
let distanceToRestaurantsRequest = database.makeRequest(with: query)
```

We can execute the query passing in our latitude and longitude:

<!-- test: XLDocumentationTests.testDocumentationCustomFunctionRegistrationAndExecution -->
```swift
var request = distanceToRestaurantsRequest
request.set(myLatitude, -33.877873677687894)
request.set(myLongitude, 18.488075015723)
let restaurants = try request.fetchAll()
```
