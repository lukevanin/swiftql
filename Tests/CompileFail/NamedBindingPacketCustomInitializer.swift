import SwiftQL

@SQLBindings
struct PersonSearchBindings {
    var name: String
    var minimumAge: Int

    init(name: String) { // expected-error
        self.name = name
        self.minimumAge = 0
    }
}

// Without the diagnostic, this call compiles and silently binds 0.
func adaSearch() -> PersonSearchBindings {
    PersonSearchBindings(name: "Ada")
}
