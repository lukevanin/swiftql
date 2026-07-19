/// Stable identifiers for the Northwind real-database semantic corpus.
///
/// These identifiers are deliberately independent of XCTest method names so
/// another SQLite adapter can run and report the same cases unchanged.
public enum SQLiteNorthwindConformanceCaseID:
    String,
    CaseIterable,
    Codable,
    Hashable,
    Sendable
{
    case pinnedCorpus = "northwind.fixture.pinned-corpus"
    case quotedOrderDetails = "northwind.select.quoted-order-details"
    case orderDetailsCompoundKey = "northwind.key.order-details-compound"
    case nullableShipping = "northwind.select.nullable-shipping"
    case unicodeBlob = "northwind.value.unicode-blob"
    case deterministicPagination = "northwind.select.deterministic-pagination"
    case emptyResult = "northwind.select.empty-result"
    case customerOrderEmployeeProductJoin = "northwind.join.customer-order-employee-product"
    case leftNullManager = "northwind.join.left-null-manager"
    case order10248Total = "northwind.aggregate.order-10248-total"
    case groupedHaving = "northwind.aggregate.grouped-having"
    case emptyAggregateNull = "northwind.aggregate.empty-null"
    case packagedViewDecoding = "northwind.view.packaged-decoding"
    case productsAboveAverage = "northwind.subquery.products-above-average"
    case customerSupplierCities = "northwind.compound.customer-supplier-cities"
    case cteOrderSubtotals = "northwind.cte.order-subtotals"
    case crudTemporaryCopy = "northwind.dml.crud-temporary-copy"
    case throwingRollback = "northwind.transaction.throwing-rollback"
}


/// Pinned values that make accidental replacement or truncation of the
/// Northwind database immediately visible to every corpus consumer.
public enum SQLiteNorthwindConformanceFixtures {
    public static let customerCount = 93
    public static let orderCount = 830
    public static let orderDetailCount = 2_155
    public static let productCount = 77

    public static let sentinelOrderID = 10_248
    public static let sentinelOrderDetails: [OrderDetailSentinel] = [
        OrderDetailSentinel(productID: 11, unitPrice: 14, quantity: 12, discount: 0),
        OrderDetailSentinel(productID: 42, unitPrice: 9.8, quantity: 10, discount: 0),
        OrderDetailSentinel(productID: 72, unitPrice: 34.8, quantity: 5, discount: 0),
    ]
    public static let sentinelOrderSubtotal = 440.0
    public static let nullableShippingOrderID = 11_008

    public static let unicodeCustomerID = "ANATR"
    public static let unicodeCustomerCompany = "Ana Trujillo Emparedados y helados"
    public static let unicodeCustomerCity = "México D.F."
    public static let unicodeProductID = 24
    public static let unicodeProductName = "Guaraná Fantástica"
    public static let blobEmployeeID = 1
    public static let blobEmployeePhotoByteCount = 12_315

    public struct OrderDetailSentinel: Equatable, Sendable {
        public let productID: Int
        public let unitPrice: Double
        public let quantity: Int
        public let discount: Double

        public init(
            productID: Int,
            unitPrice: Double,
            quantity: Int,
            discount: Double
        ) {
            self.productID = productID
            self.unitPrice = unitPrice
            self.quantity = quantity
            self.discount = discount
        }
    }
}
