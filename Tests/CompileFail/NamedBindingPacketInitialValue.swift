import SwiftQL

@SQLBindings
struct PersonSearchBindings {
    var name: String
    var minimumAge: Int = 0 // expected-error
}

// Without the diagnostic, this call compiles and silently binds 0.
func adaSearch() -> PersonSearchBindings {
    PersonSearchBindings(name: "Ada")
}
