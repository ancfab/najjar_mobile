// Cross-cutting responsiveness checks for the responsive-layout audit:
// small/standard/large phone and tablet widths, an increased system text
// scale, and a landscape orientation — verifying every major screen and
// the app's bottom sheets render without RenderFlex/layout overflow
// exceptions. Per-screen functional behavior is already covered by the
// other test files; these tests exist purely to catch layout regressions.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/data/country_codes.dart';
import 'package:anc_fabrics/main.dart';
import 'package:anc_fabrics/models/account_transaction.dart';
import 'package:anc_fabrics/models/fabric_order_filter.dart';
import 'package:anc_fabrics/models/fabric_specs.dart';
import 'package:anc_fabrics/screens/account_balance_screen.dart';
import 'package:anc_fabrics/screens/account_transaction_details_screen.dart';
import 'package:anc_fabrics/screens/contact_us_screen.dart';
import 'package:anc_fabrics/screens/edit_profile_screen.dart';
import 'package:anc_fabrics/screens/home_screen.dart';
import 'package:anc_fabrics/screens/invoice_details_screen.dart';
import 'package:anc_fabrics/screens/invoices_screen.dart';
import 'package:anc_fabrics/screens/order_detail_screen.dart';
import 'package:anc_fabrics/screens/orders_screen.dart';
import 'package:anc_fabrics/screens/scan_stock_screen.dart';
import 'package:anc_fabrics/screens/support_screen.dart';
import 'package:anc_fabrics/widgets/account_balance_hero_card.dart';
import 'package:anc_fabrics/widgets/country_code_picker.dart';
import 'package:anc_fabrics/widgets/custom_bottom_nav.dart';
import 'package:anc_fabrics/widgets/fabric_specs_sheet.dart';
import 'package:anc_fabrics/widgets/invoice_action_buttons.dart';
import 'package:anc_fabrics/widgets/order_filter_sheet.dart';
import 'package:anc_fabrics/widgets/scan_fabric_button.dart';

import 'helpers/fake_account_balance_service.dart';
import 'helpers/fake_account_statement_exporter.dart';
import 'helpers/fake_invoice_document_actions.dart';
import 'helpers/fake_invoice_pdf_service.dart';

// Recommended test dimensions from the audit brief: small, standard, and
// large phones, plus a tablet.
const _smallPhone = Size(320, 568);
const _standardPhone = Size(375, 667);
const _largePhone = Size(430, 932);
const _tablet = Size(768, 1024);
const _sizes = [_smallPhone, _standardPhone, _largePhone, _tablet];

Future<void> _setSize(
  WidgetTester tester,
  Size size, {
  double textScaleFactor = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (textScaleFactor != 1.0) {
    tester.platformDispatcher.textScaleFactorTestValue = textScaleFactor;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
}

/// Every screen under test either has a bare `Future.delayed` mock fetch or
/// none at all; 700ms covers the longest of them (the Orders/Home mock
/// services' ~600ms delay) so `pumpAndSettle` always has real data to settle
/// on instead of a perpetual loading state.
Future<void> _settleFetch(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
}

void main() {
  group('Login screen', () {
    for (final size in _sizes) {
      testWidgets(
        'No overflow at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _setSize(tester, size);
          await tester.pumpWidget(const MyApp());
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('No overflow at 1.3x system text scale', (tester) async {
      await _setSize(tester, _standardPhone, textScaleFactor: 1.3);
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('No overflow in landscape on a small phone', (tester) async {
      await _setSize(tester, const Size(568, 320));
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Home screen', () {
    Future<void> pumpHome(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await _settleFetch(tester);
    }

    for (final size in _sizes) {
      testWidgets(
        'No overflow at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _setSize(tester, size);
          await pumpHome(tester);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('No overflow at 1.3x system text scale', (tester) async {
      await _setSize(tester, _standardPhone, textScaleFactor: 1.3);
      await pumpHome(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Content column is width-capped on tablet', (tester) async {
      await _setSize(tester, _tablet);
      await pumpHome(tester);

      final buttonWidth = tester.getSize(find.byType(ScanFabricButton)).width;
      // The button stretches to fill the (max-width-capped) content
      // column; on a 768px-wide tablet a full-bleed button would be well
      // over 700px, so this confirms the tablet max-width constraint is
      // actually applied rather than the phone layout simply stretching.
      expect(buttonWidth, lessThan(700));
    });
  });

  group('Orders screen', () {
    for (final size in _sizes) {
      testWidgets(
        'No overflow at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _setSize(tester, size);
          await tester.pumpWidget(const MaterialApp(home: OrdersScreen()));
          await _settleFetch(tester);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('No overflow at 1.5x system text scale', (tester) async {
      await _setSize(tester, _standardPhone, textScaleFactor: 1.5);
      await tester.pumpWidget(const MaterialApp(home: OrdersScreen()));
      await _settleFetch(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('No overflow in landscape', (tester) async {
      await _setSize(tester, const Size(844, 390));
      await tester.pumpWidget(const MaterialApp(home: OrdersScreen()));
      await _settleFetch(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('Order Detail screen', () {
    for (final size in _sizes) {
      testWidgets(
        'No overflow at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _setSize(tester, size);
          await tester.pumpWidget(
            const MaterialApp(home: OrderDetailScreen(orderId: '#ORD-8829')),
          );
          await _settleFetch(tester);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('No overflow at 1.5x system text scale', (tester) async {
      await _setSize(tester, _standardPhone, textScaleFactor: 1.5);
      await tester.pumpWidget(
        const MaterialApp(home: OrderDetailScreen(orderId: '#ORD-8829')),
      );
      await _settleFetch(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('Scan Stock screen', () {
    for (final size in _sizes) {
      testWidgets(
        'No overflow at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _setSize(tester, size);
          await tester.pumpWidget(const MaterialApp(home: ScanStockScreen()));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'No overflow in a short landscape height (e.g. small-phone landscape)',
      (tester) async {
        await _setSize(tester, const Size(568, 320));
        await tester.pumpWidget(const MaterialApp(home: ScanStockScreen()));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('No overflow at 1.5x system text scale', (tester) async {
      await _setSize(tester, _standardPhone, textScaleFactor: 1.5);
      await tester.pumpWidget(const MaterialApp(home: ScanStockScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Bottom sheets', () {
    testWidgets(
      'Order filter sheet has no overflow at small width + 1.5x text scale',
      (tester) async {
        await _setSize(tester, _smallPhone, textScaleFactor: 1.5);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) => const OrderFilterSheet(
                      // Custom date range adds two extra fields, and a long
                      // fabric type list wraps across several lines — both
                      // push this sheet closer to overflowing than its
                      // default state.
                      initialFilter: FabricOrderFilter(
                        dateRange: DateRangeFilter.custom,
                      ),
                      fabricTypeOptions: [
                        'Cotton',
                        'Wool',
                        'Silk',
                        'Linen',
                        'Polyester',
                        'Denim',
                        'Velvet',
                      ],
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Filter Orders'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Fabric specs sheet has no overflow at small width + 1.5x text scale',
      (tester) async {
        await _setSize(tester, _smallPhone, textScaleFactor: 1.5);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showFabricSpecsSheet(
                    context,
                    const FabricSpecs(
                      fabricName: 'Premium Cotton Twill',
                      sku: 'SKU-8829',
                      color: 'Indigo Blue',
                      weight: '320 GSM',
                      quantity: '280 meters',
                      composition: '100% Cotton',
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Fabric Specs'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Country code picker sheet has no overflow at small width + 1.5x '
      'text scale',
      (tester) async {
        await _setSize(tester, _smallPhone, textScaleFactor: 1.5);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CountryCodePicker(
                selectedCountry: kDefaultCountryCode,
                onChanged: (_) {},
              ),
            ),
          ),
        );

        await tester.tap(find.text(kDefaultCountryCode.dialCode));
        await tester.pumpAndSettle();

        expect(find.text('Select country code'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Support screen', () {
    for (final size in _sizes) {
      testWidgets(
        'No overflow at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _setSize(tester, size);
          await tester.pumpWidget(const MaterialApp(home: SupportScreen()));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('No overflow at 1.5x system text scale', (tester) async {
      await _setSize(tester, _standardPhone, textScaleFactor: 1.5);
      await tester.pumpWidget(const MaterialApp(home: SupportScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('No overflow in landscape', (tester) async {
      await _setSize(tester, const Size(844, 390));
      await tester.pumpWidget(const MaterialApp(home: SupportScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Content column is width-capped on tablet', (tester) async {
      await _setSize(tester, _tablet);
      await tester.pumpWidget(const MaterialApp(home: SupportScreen()));
      await tester.pumpAndSettle();

      final cardWidth = tester
          .getSize(find.byKey(const ValueKey('support-corporate-office-card')))
          .width;
      // On a 768px-wide tablet a full-bleed card would be well over 700px,
      // so this confirms the tablet max-width constraint is actually
      // applied rather than the phone layout simply stretching.
      expect(cardWidth, lessThan(700));
    });
  });

  group('Contact Us screen', () {
    for (final size in _sizes) {
      testWidgets(
        'No overflow at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _setSize(tester, size);
          await tester.pumpWidget(const MaterialApp(home: ContactUsScreen()));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('No overflow at 1.5x system text scale', (tester) async {
      await _setSize(tester, _standardPhone, textScaleFactor: 1.5);
      await tester.pumpWidget(const MaterialApp(home: ContactUsScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('No overflow in landscape', (tester) async {
      await _setSize(tester, const Size(844, 390));
      await tester.pumpWidget(const MaterialApp(home: ContactUsScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Content column is width-capped on tablet', (tester) async {
      await _setSize(tester, _tablet);
      await tester.pumpWidget(const MaterialApp(home: ContactUsScreen()));
      await tester.pumpAndSettle();

      final cardWidth = tester
          .getSize(find.byKey(const ValueKey('contact-main-office-card')))
          .width;
      // On a 768px-wide tablet a full-bleed card would be well over 700px,
      // so this confirms the tablet max-width constraint is actually
      // applied rather than the phone layout simply stretching.
      expect(cardWidth, lessThan(700));
    });
  });

  group('Placeholder screens', () {
    testWidgets(
      'Invoices screen has no overflow at small width + 1.5x text scale',
      (tester) async {
        await _setSize(tester, _smallPhone, textScaleFactor: 1.5);
        await tester.pumpWidget(const MaterialApp(home: InvoicesScreen()));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Account Balance screen', () {
    Future<void> pumpAccountBalance(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AccountBalanceScreen(
            service: FakeAccountBalanceService(),
            exporter: FakeAccountStatementExporter(),
          ),
        ),
      );
      await _settleFetch(tester);
    }

    for (final size in _sizes) {
      testWidgets(
        'No overflow at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _setSize(tester, size);
          await pumpAccountBalance(tester);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('No overflow at 1.5x system text scale', (tester) async {
      await _setSize(tester, _standardPhone, textScaleFactor: 1.5);
      await pumpAccountBalance(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('No overflow in landscape', (tester) async {
      await _setSize(tester, const Size(844, 390));
      await pumpAccountBalance(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Content column is width-capped on tablet', (tester) async {
      await _setSize(tester, _tablet);
      await pumpAccountBalance(tester);

      final cardWidth = tester
          .getSize(find.byType(AccountBalanceHeroCard))
          .width;
      // On a 768px-wide tablet a full-bleed card would be well over 700px,
      // so this confirms the tablet max-width constraint is actually
      // applied rather than the phone layout simply stretching.
      expect(cardWidth, lessThan(700));
    });
  });

  group('Account Transaction Details screen', () {
    final transaction = AccountTransaction(
      id: 'txn-client-deposit',
      label: 'Client Deposit',
      amount: 15000,
      type: AccountTransactionType.credit,
      occurredAt: DateTime.utc(2023, 10, 26),
      category: AccountTransactionCategory.deposit,
      reference: 'REF-20231026-CD',
    );

    Future<void> pumpTransactionDetails(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AccountTransactionDetailsScreen(transaction: transaction),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final size in _sizes) {
      testWidgets(
        'No overflow at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _setSize(tester, size);
          await pumpTransactionDetails(tester);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('No overflow at 1.5x system text scale', (tester) async {
      await _setSize(tester, _standardPhone, textScaleFactor: 1.5);
      await pumpTransactionDetails(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('No overflow in landscape', (tester) async {
      await _setSize(tester, const Size(844, 390));
      await pumpTransactionDetails(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Content column is width-capped on tablet', (tester) async {
      await _setSize(tester, _tablet);
      await pumpTransactionDetails(tester);

      final cardWidth = tester
          .getSize(
            find.byKey(const ValueKey('account-transaction-details-card')),
          )
          .width;
      // On a 768px-wide tablet a full-bleed card would be well over 700px,
      // so this confirms the tablet max-width constraint is actually
      // applied rather than the phone layout simply stretching.
      expect(cardWidth, lessThan(700));
    });
  });

  group('Invoice Details screen', () {
    Future<void> pumpInvoiceDetails(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: InvoiceDetailsScreen(
            invoiceNumber: '#INV-8821',
            pdfService: FakeInvoicePdfService(),
            documentActions: FakeInvoiceDocumentActions(),
          ),
        ),
      );
      await _settleFetch(tester);
    }

    for (final size in _sizes) {
      testWidgets(
        'No overflow at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _setSize(tester, size);
          await pumpInvoiceDetails(tester);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('No overflow at 1.5x system text scale', (tester) async {
      await _setSize(tester, _standardPhone, textScaleFactor: 1.5);
      await pumpInvoiceDetails(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('No overflow in landscape', (tester) async {
      await _setSize(tester, const Size(844, 390));
      await pumpInvoiceDetails(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Content column is width-capped on tablet', (tester) async {
      await _setSize(tester, _tablet);
      await pumpInvoiceDetails(tester);

      final actionsWidth = tester
          .getSize(find.byType(InvoiceActionButtons))
          .width;
      // On a 768px-wide tablet full-bleed content would be well over
      // 700px, so this confirms the tablet max-width constraint is
      // actually applied rather than the phone layout simply stretching.
      expect(actionsWidth, lessThan(700));
    });
  });

  group('Bottom navigation', () {
    Future<void> pumpBottomNav(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CustomBottomNav(currentIndex: 0, onTap: (_) {})),
        ),
      );
    }

    for (final size in _sizes) {
      testWidgets('All four tabs render without overflow at '
          '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        await _setSize(tester, size);
        await pumpBottomNav(tester);
        expect(find.text('Home'), findsOneWidget);
        expect(find.text('Orders'), findsOneWidget);
        expect(find.text('Support'), findsOneWidget);
        expect(find.text('Profile'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'Labels stay on one line (ellipsized, not overflowed) at 2x system '
      'text scale on the smallest supported phone width',
      (tester) async {
        await _setSize(tester, _smallPhone, textScaleFactor: 2.0);
        await pumpBottomNav(tester);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Edit Profile screen', () {
    testWidgets('No overflow at small width + 1.5x text scale', (tester) async {
      await _setSize(tester, _smallPhone, textScaleFactor: 1.5);
      await tester.pumpWidget(MaterialApp(home: EditProfileScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
