import Foundation
import Lighter

/// Fixed anchor that forces the Enlighter-generated database type to be
/// type-checked by this module. Lighter exposes no user-written table or
/// query declarations, so `schema.sql` is the only thing that scales.
public enum ConsumerAnchor {
    public static var generatedDatabaseDescription: String {
        String(describing: ScaleSchema.self)
    }
}
