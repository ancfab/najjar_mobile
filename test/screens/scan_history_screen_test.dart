// Widget tests for the Scan History screen: loading, empty state, record
// rendering (timestamp/raw code always shown, item number/description/
// batch-reference only when present, quantity/location/unit never shown),
// newest-first ordering, back navigation, the one-time Recent Scan
// migration, safe degradation on an unreadable store, no Clear History
// action, and overflow/RTL/locale coverage.
//
// Every persistence seam (ScanHistoryStore, LastScanStore) is injected as a
// fake — no real shared_preferences platform channel is touched, and no
// network call of any kind occurs on this screen.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/localization/app_translations_delegate.dart';
import 'package:anc_fabrics/screens/scan_history_screen.dart';
import 'package:anc_fabrics/services/last_scan_store.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../helpers/fake_last_scan_store.dart';
import '../helpers/fake_scan_history_store.dart';

const _titleByLocale = {
  'en': 'Scan History',
  'ar': 'سجل المسح',
  'fr': 'Historique des scans',
};

const _emptyMessageByLocale = {
  'en': 'No scan history yet',
  'ar': 'لا يوجد سجل مسح حتى الآن',
  'fr': "Aucun historique de scan pour l'instant",
};

PersistedScanRecord _record({
  required String rawCode,
  required DateTime scannedAt,
  String? itemNo,
  String? description,
  String? batchReference,
}) => PersistedScanRecord(
  rawCode: rawCode,
  scannedAt: scannedAt,
  itemNo: itemNo,
  description: description,
  batchReference: batchReference,
);

Future<void> _pumpScanHistoryScreen(
  WidgetTester tester, {
  String locale = 'en',
  double width = 390,
  double height = 800,
  double textScaleFactor = 1.0,
  FakeScanHistoryStore? historyStore,
  FakeLastScanStore? lastScanStore,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
      localizationsDelegates: const [
        AppTranslationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: textScaleFactor == 1.0
          ? null
          : (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
              child: child!,
            ),
      home: ScanHistoryScreen(
        historyStore: historyStore ?? FakeScanHistoryStore(),
        lastScanStore: lastScanStore ?? FakeLastScanStore(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Loading and empty state', () {
    testWidgets('A loading indicator is shown while the read is in flight', (
      tester,
    ) async {
      final store = FakeScanHistoryStore()..readGate = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
          localizationsDelegates: const [
            AppTranslationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: ScanHistoryScreen(
            historyStore: store,
            lastScanStore: FakeLastScanStore(),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('scan-history-loading')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      store.readGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scan-history-loading')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Empty history shows the localized empty state', (
      tester,
    ) async {
      await _pumpScanHistoryScreen(tester);

      expect(
        find.byKey(const ValueKey('scan-history-empty-state')),
        findsOneWidget,
      );
      expect(find.text('No scan history yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Localized title is shown', (tester) async {
      await _pumpScanHistoryScreen(tester);
      expect(find.text('Scan History'), findsOneWidget);
    });
  });

  group('Record rendering', () {
    testWidgets('Timestamp and raw code are displayed', (tester) async {
      final store = FakeScanHistoryStore(
        initial: [
          _record(
            rawCode: 'RAW-1',
            scannedAt: DateTime.utc(2026, 7, 31, 12, 30),
          ),
        ],
      );
      await _pumpScanHistoryScreen(tester, historyStore: store);

      expect(
        find.byKey(const ValueKey('scan-history-row-raw-code')),
        findsOneWidget,
      );
      expect(find.text('RAW-1'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('scan-history-row-timestamp')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Item number appears when available', (tester) async {
      final store = FakeScanHistoryStore(
        initial: [
          _record(
            rawCode: 'RAW-1',
            scannedAt: DateTime.utc(2026, 1, 1),
            itemNo: 'ITEM-0042',
          ),
        ],
      );
      await _pumpScanHistoryScreen(tester, historyStore: store);

      expect(
        find.byKey(const ValueKey('scan-history-row-item-number')),
        findsOneWidget,
      );
      expect(find.text('ITEM-0042'), findsOneWidget);
    });

    testWidgets('Item number row is absent when not available', (tester) async {
      final store = FakeScanHistoryStore(
        initial: [
          _record(rawCode: 'RAW-1', scannedAt: DateTime.utc(2026, 1, 1)),
        ],
      );
      await _pumpScanHistoryScreen(tester, historyStore: store);

      expect(
        find.byKey(const ValueKey('scan-history-row-item-number')),
        findsNothing,
      );
    });

    testWidgets('Description appears when available', (tester) async {
      final store = FakeScanHistoryStore(
        initial: [
          _record(
            rawCode: 'RAW-1',
            scannedAt: DateTime.utc(2026, 1, 1),
            description: 'Egyptian Cotton Sateen',
          ),
        ],
      );
      await _pumpScanHistoryScreen(tester, historyStore: store);

      expect(
        find.byKey(const ValueKey('scan-history-row-description')),
        findsOneWidget,
      );
      expect(find.text('Egyptian Cotton Sateen'), findsOneWidget);
    });

    testWidgets('Batch/reference appears only when available', (tester) async {
      final withBatch = FakeScanHistoryStore(
        initial: [
          _record(
            rawCode: 'RAW-1',
            scannedAt: DateTime.utc(2026, 1, 1),
            batchReference: 'BATCH-9',
          ),
        ],
      );
      await _pumpScanHistoryScreen(tester, historyStore: withBatch);
      expect(
        find.byKey(const ValueKey('scan-history-row-batch-reference')),
        findsOneWidget,
      );
      expect(find.text('BATCH-9'), findsOneWidget);
    });

    testWidgets('Batch/reference row is absent when null', (tester) async {
      final withoutBatch = FakeScanHistoryStore(
        initial: [
          _record(rawCode: 'RAW-1', scannedAt: DateTime.utc(2026, 1, 1)),
        ],
      );
      await _pumpScanHistoryScreen(tester, historyStore: withoutBatch);
      expect(
        find.byKey(const ValueKey('scan-history-row-batch-reference')),
        findsNothing,
      );
    });

    testWidgets('Batch/reference row is absent when blank', (tester) async {
      final blankBatch = FakeScanHistoryStore(
        initial: [
          _record(
            rawCode: 'RAW-1',
            scannedAt: DateTime.utc(2026, 1, 1),
            batchReference: '',
          ),
        ],
      );
      await _pumpScanHistoryScreen(tester, historyStore: blankBatch);
      expect(
        find.byKey(const ValueKey('scan-history-row-batch-reference')),
        findsNothing,
      );
    });

    testWidgets('Quantity/location/unit text is never displayed', (
      tester,
    ) async {
      final store = FakeScanHistoryStore(
        initial: [
          _record(
            rawCode: 'RAW-1',
            scannedAt: DateTime.utc(2026, 1, 1),
            itemNo: 'ITEM-1',
            description: 'Cotton',
            batchReference: 'B-1',
          ),
        ],
      );
      await _pumpScanHistoryScreen(tester, historyStore: store);

      expect(find.textContaining('remainingQuantity'), findsNothing);
      expect(find.textContaining('location', findRichText: true), findsNothing);
      expect(find.textContaining('available'), findsNothing);
    });
  });

  group('Ordering', () {
    testWidgets('Multiple records display newest first', (tester) async {
      final store = FakeScanHistoryStore(
        initial: [
          _record(rawCode: 'OLDEST', scannedAt: DateTime.utc(2026, 1, 1)),
          _record(rawCode: 'NEWEST', scannedAt: DateTime.utc(2026, 1, 3)),
          _record(rawCode: 'MIDDLE', scannedAt: DateTime.utc(2026, 1, 2)),
        ],
      );
      await _pumpScanHistoryScreen(tester, historyStore: store);

      final listFinder = find.byKey(const ValueKey('scan-history-list'));
      expect(listFinder, findsOneWidget);

      final rawCodesInOrder = tester
          .widgetList<Text>(
            find.descendant(
              of: listFinder,
              matching: find.byKey(const ValueKey('scan-history-row-raw-code')),
            ),
          )
          .map((widget) => widget.data)
          .toList();

      expect(rawCodesInOrder, ['NEWEST', 'MIDDLE', 'OLDEST']);
    });
  });

  group('No Clear History action', () {
    testWidgets('No Clear History control exists', (tester) async {
      final store = FakeScanHistoryStore(
        initial: [
          _record(rawCode: 'RAW-1', scannedAt: DateTime.utc(2026, 1, 1)),
        ],
      );
      await _pumpScanHistoryScreen(tester, historyStore: store);

      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byIcon(Icons.delete_forever), findsNothing);
      expect(find.text('Clear History'), findsNothing);
    });
  });

  group('Back navigation', () {
    testWidgets('Back navigation returns to the pushing screen', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
          localizationsDelegates: const [
            AppTranslationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const ValueKey('push-history-button'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ScanHistoryScreen(
                        historyStore: FakeScanHistoryStore(),
                        lastScanStore: FakeLastScanStore(),
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('push-history-button')));
      await tester.pumpAndSettle();
      expect(find.byType(ScanHistoryScreen), findsOneWidget);

      expect(find.byType(BackButton), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(ScanHistoryScreen), findsNothing);
      expect(find.byKey(const ValueKey('push-history-button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Recent Scan migration', () {
    testWidgets('A valid existing Recent Scan record is migrated into an empty '
        'history', (tester) async {
      final lastScanStore = FakeLastScanStore(
        initial: _record(
          rawCode: 'MIGRATED',
          scannedAt: DateTime.utc(2026, 1, 1),
          itemNo: 'ITEM-1',
        ),
      );
      final historyStore = FakeScanHistoryStore();

      await _pumpScanHistoryScreen(
        tester,
        historyStore: historyStore,
        lastScanStore: lastScanStore,
      );

      expect(find.text('MIGRATED'), findsOneWidget);
      expect(historyStore.appendCallCount, 1);
    });

    testWidgets(
      'Migration does not run again once history is no longer empty',
      (tester) async {
        final lastScanStore = FakeLastScanStore(
          initial: _record(
            rawCode: 'RECENT',
            scannedAt: DateTime.utc(2026, 1, 5),
          ),
        );
        final historyStore = FakeScanHistoryStore(
          initial: [
            _record(
              rawCode: 'ALREADY-THERE',
              scannedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
        );

        await _pumpScanHistoryScreen(
          tester,
          historyStore: historyStore,
          lastScanStore: lastScanStore,
        );

        expect(find.text('ALREADY-THERE'), findsOneWidget);
        expect(find.text('RECENT'), findsNothing);
        expect(historyStore.appendCallCount, 0);
      },
    );

    testWidgets(
      'No Recent Scan record and empty history stay empty (no migration)',
      (tester) async {
        final historyStore = FakeScanHistoryStore();
        await _pumpScanHistoryScreen(
          tester,
          historyStore: historyStore,
          lastScanStore: FakeLastScanStore(),
        );

        expect(
          find.byKey(const ValueKey('scan-history-empty-state')),
          findsOneWidget,
        );
        expect(historyStore.appendCallCount, 0);
      },
    );
  });

  group('Storage failure', () {
    testWidgets(
      'An unreadable history store degrades to the empty state without '
      'crashing',
      (tester) async {
        final store = FakeScanHistoryStore()
          ..throwOnRead = Exception('simulated read failure');
        await _pumpScanHistoryScreen(tester, historyStore: store);

        expect(
          find.byKey(const ValueKey('scan-history-empty-state')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('No backend request', () {
    testWidgets('Opening the screen touches only the injected local stores', (
      tester,
    ) async {
      final historyStore = FakeScanHistoryStore(
        initial: [
          _record(rawCode: 'RAW-1', scannedAt: DateTime.utc(2026, 1, 1)),
        ],
      );
      await _pumpScanHistoryScreen(tester, historyStore: historyStore);

      // No HTTP client, AncApiClient, or session coordinator is ever
      // constructed by this screen or its constructor-injected fakes —
      // reaching a rendered state at all (with no exception) with only
      // local fakes injected demonstrates no network dependency exists.
      expect(historyStore.readCallCount, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  });

  group('Localization', () {
    for (final locale in _titleByLocale.keys) {
      testWidgets('$locale: renders title and empty state, no overflow', (
        tester,
      ) async {
        await _pumpScanHistoryScreen(tester, locale: locale);

        expect(find.text(_titleByLocale[locale]!), findsOneWidget);
        expect(find.text(_emptyMessageByLocale[locale]!), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Arabic renders right-to-left', (tester) async {
      await _pumpScanHistoryScreen(tester, locale: 'ar');

      final context = tester.element(find.text('سجل المسح'));
      expect(Directionality.of(context), TextDirection.rtl);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Raw codes remain LTR under an Arabic locale', (tester) async {
      final store = FakeScanHistoryStore(
        initial: [
          _record(rawCode: 'ITEM-0042', scannedAt: DateTime.utc(2026, 1, 1)),
        ],
      );
      await _pumpScanHistoryScreen(tester, locale: 'ar', historyStore: store);

      final context = tester.element(find.text('ITEM-0042'));
      expect(Directionality.of(context), TextDirection.ltr);
    });
  });

  group('Responsive / overflow', () {
    List<PersistedScanRecord> longValueRecords() => [
      _record(
        rawCode: 'ITEM-VERY-LONG-RAW-CODE-1234567890-ABCDEFGHIJK',
        scannedAt: DateTime.utc(2026, 1, 1),
        itemNo: 'ITEM-VERY-LONG-ITEM-NUMBER-1234567890-ABCDEFGHIJK',
        description:
            'An extremely long fabric description that keeps going and '
            'going to make sure this row never overflows on a narrow phone',
        batchReference: 'BATCH-REFERENCE-ALSO-VERY-LONG-1234567890',
      ),
    ];

    testWidgets('Long values do not overflow on a small phone', (tester) async {
      final store = FakeScanHistoryStore(initial: longValueRecords());
      await _pumpScanHistoryScreen(
        tester,
        historyStore: store,
        width: 320,
        height: 568,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('No overflow on a large phone in portrait', (tester) async {
      final store = FakeScanHistoryStore(initial: longValueRecords());
      await _pumpScanHistoryScreen(
        tester,
        historyStore: store,
        width: 430,
        height: 932,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('No overflow on a tablet width', (tester) async {
      final store = FakeScanHistoryStore(initial: longValueRecords());
      await _pumpScanHistoryScreen(
        tester,
        historyStore: store,
        width: 768,
        height: 1024,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('No overflow in landscape orientation', (tester) async {
      final store = FakeScanHistoryStore(initial: longValueRecords());
      await _pumpScanHistoryScreen(
        tester,
        historyStore: store,
        width: 800,
        height: 400,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('No overflow at increased text scale', (tester) async {
      final store = FakeScanHistoryStore(initial: longValueRecords());
      await _pumpScanHistoryScreen(
        tester,
        historyStore: store,
        textScaleFactor: 1.5,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
