import '../models/business_central/sales_order_line.dart';
import 'demo_sales_order_lines_data_source.dart';
import 'order_detail_data_source.dart';

/// TEMPORARY CLIENT DEMO MODE [OrderDetailDataSource]: resolves every line
/// for [documentNo] from the same canonical
/// [DemoSalesOrderLinesDataSource.mockLines] dataset the Orders list demo
/// source shows — so Order Detail always agrees with whatever
/// `DemoSalesOrderLinesDataSource` displayed for that `Document_No`, with no
/// second copy of the demo dataset to drift out of sync. Never calls the
/// live sales-orders endpoint. Selected in place of [LiveOrderDetailDataSource]
/// only when [DemoConfig.useDemoOrders] (`demo_config.dart`) is `true`; see
/// `resolveDefaultOrderDetailDataSource` in `order_detail_screen.dart`.
///
/// An unrecognized `Document_No` resolves to an empty list, matching the
/// live contract's "HTTP 200 + empty `data`" not-found signal — so
/// `OrderDetailScreen` shows the same Order Not Found state it would for a
/// genuinely missing live order.
class DemoOrderDetailDataSource implements OrderDetailDataSource {
  const DemoOrderDetailDataSource();

  @override
  Future<List<BusinessCentralSalesOrderLine>> fetchOrder({
    required String documentNo,
  }) async {
    return DemoSalesOrderLinesDataSource.mockLines
        .where((line) => line.documentNo == documentNo)
        .toList(growable: false);
  }
}
