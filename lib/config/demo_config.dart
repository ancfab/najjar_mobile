/// Purpose: Holds temporary, client-demo-only overrides for Home screen
/// dashboard cards and the Orders screen — kept separate from [ApiConfig]
/// (`api_config.dart`) since these flags are not network configuration and
/// are expected to be short-lived.
///
/// Must not: grow into a general feature-flag system. This exists solely so
/// the Current Balance card and the Orders (Fabric Orders) screen can show
/// mock data during client demos without touching the live Business Central
/// integrations underneath them — see `CurrentBalanceService`/
/// `LiveCurrentBalanceDataSource` and `SalesOrderLinesService`/
/// `LiveSalesOrderLinesDataSource`, all of which remain fully intact and
/// reachable by setting the relevant flag back to `false`.
class DemoConfig {
  DemoConfig._();

  // TEMPORARY CLIENT DEMO MODE.
  // Set to false to restore the live Business Central Current Balance integration.
  static const bool useDemoCurrentBalance = true;

  // TEMPORARY CLIENT DEMO MODE.
  // Set to false to restore the live Business Central Orders integration.
  static const bool useDemoOrders = true;
}
