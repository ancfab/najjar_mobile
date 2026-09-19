import '../models/business_central/zebra_sales_order_line.dart';
import 'zebra_order_detail_data_source.dart';

/// TEMPORARY CLIENT DEMO MODE [ZebraOrderDetailDataSource]: always returns no
/// Zebra detail, since there is no demo Zebra dataset to draw from and every
/// demo order is fake to begin with — there is nothing real for a Zebra
/// lookup to correlate against. Selected in place of
/// [LiveZebraOrderDetailDataSource] only when [DemoConfig.useDemoOrders]
/// (`demo_config.dart`) is `true`; see `resolveDefaultZebraOrderDetailDataSource`
/// in `order_detail_screen.dart`. Never calls the live Zebra endpoint.
///
/// Harmless by construction: `OrderDetailScreen` already treats an empty
/// Zebra result as "show the plain order-line view, nothing more" (see that
/// screen's doc comment), so demo mode's Order Detail screen looks exactly
/// as it did before this enrichment existed.
class DemoZebraOrderDetailDataSource implements ZebraOrderDetailDataSource {
  const DemoZebraOrderDetailDataSource();

  @override
  Future<List<BusinessCentralZebraSalesOrderLine>> fetchOrder({
    required String documentNo,
  }) async => const [];
}
