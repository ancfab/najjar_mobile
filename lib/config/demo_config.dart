/// Purpose: Holds temporary, client-demo-only overrides for Home screen
/// dashboard cards and the Orders → Order Detail → Invoice flow — kept
/// separate from [ApiConfig] (`api_config.dart`) since these flags are not
/// network configuration and are expected to be short-lived.
///
/// Must not: grow into a general feature-flag system. This exists solely so
/// the Current Balance card and the entire Orders (Fabric Orders) → Order
/// Detail → Invoice flow can show mock data during client demos without
/// touching the live Business Central integrations underneath them — see
/// `CurrentBalanceService`/`LiveCurrentBalanceDataSource` and
/// `SalesOrderLinesService`/`LiveSalesOrderLinesDataSource`/
/// `LiveOrderDetailDataSource`/`LiveInvoiceLookupDataSource`, all of which
/// remain fully intact and reachable by setting the relevant flag back to
/// `false`. `useDemoOrders` gates all three of `OrdersScreen`,
/// `OrderDetailScreen`'s order-line fetch, and `OrderDetailScreen`'s Invoice
/// lookup together (see `resolveDefaultSalesOrderLinesDataSource`,
/// `resolveDefaultOrderDetailDataSource`,
/// `resolveDefaultInvoiceLookupDataSource`) so the three screens can never
/// disagree about demo vs. live.
class DemoConfig {
  DemoConfig._();

  // TEMPORARY CLIENT DEMO MODE.
  // Set to false to restore the live Business Central Current Balance integration.
  static const bool useDemoCurrentBalance = false;

  // TEMPORARY CLIENT DEMO MODE.
  // Set to false to restore the live Business Central Orders integration.
  static const bool useDemoOrders = false;
}
