import 'package:flutter/foundation.dart';

import '../config/api_config.dart';
import 'business_central_error_mapper.dart';
import 'current_balance_data_source.dart';
import 'current_balance_service.dart';
import 'customer_details_service.dart';
import 'ledger_entries_service.dart';

/// Purpose: Resolves the Current Balance in two parallel requests instead of
/// a full ledger sweep, so the Home card lands in about the time one request
/// takes rather than one per ledger page.
///
/// Why this exists: [LiveCurrentBalanceDataSource] fetches *every* page of
/// the customer's ledger before it can show anything. Those fetches are
/// sequential, so a long ledger on a slow connection left the card spinning
/// for 10–15 seconds. The balance itself is already available as a single
/// scalar from the customer-details endpoint — the very figure the Account
/// Balance screen's hero card shows — so Home now reads that instead, and
/// the two screens can no longer disagree about the customer's balance.
///
/// The customer-details contract carries no currency code, and this app
/// never guesses one, so the first ledger page (one request, in parallel
/// with the balance) supplies it: a customer has one currency, so the first
/// nonblank `Currency_Code` among their balance-relevant entries is it. A
/// currency lookup that fails or finds none resolves to `null`, which the
/// UI renders as a plain amount — never a guessed "$", and never a reason
/// to fail a balance that was fetched successfully.
class SnapshotCurrentBalanceDataSource implements CurrentBalanceDataSource {
  SnapshotCurrentBalanceDataSource({
    CustomerDetailsService? customerDetailsService,
    LedgerEntriesService? ledgerEntriesService,
  }) : _customerDetailsService =
           customerDetailsService ?? CustomerDetailsService(),
       _ledgerEntriesService =
           ledgerEntriesService ??
           LedgerEntriesService(perPage: ApiConfig.businessCentralMaxPerPage);

  final CustomerDetailsService _customerDetailsService;
  final LedgerEntriesService _ledgerEntriesService;

  @override
  Future<CurrentBalanceAmount> fetchCurrentBalance() async {
    // Started together: the currency lookup must not add a second round
    // trip's latency to a figure the balance request already has.
    final balanceRequest = _customerDetailsService.fetchCustomerDetails();
    final currencyRequest = _firstPageCurrencyCode();

    final details = await balanceRequest;
    final currencyCode = await currencyRequest;

    return CurrentBalanceAmount(
      amount: details.customerBalance,
      currencyCode: currencyCode,
    );
  }

  /// The currency of the customer's balance-relevant ledger entries, from
  /// the first page alone. Resolves to `null` for no entries, no nonblank
  /// code, or any failure — the balance is still worth showing without it.
  Future<String?> _firstPageCurrencyCode() async {
    try {
      await _ledgerEntriesService.loadFirstPage();
      for (final entry in _ledgerEntriesService.entries) {
        if (!entry.isOpen) continue;
        if (!isCurrentBalanceRelevantDocumentType(entry.documentType)) continue;
        final code = entry.currencyCode.trim();
        if (code.isNotEmpty) return code;
      }
    } on SessionExpiredException {
      // The session coordinator is already handling this; the balance
      // request above will surface it to the caller.
      return null;
    } catch (error) {
      debugPrint('Current Balance currency lookup failed: $error');
    }
    return null;
  }

  /// Closes both underlying services' HTTP clients.
  void close() {
    _customerDetailsService.close();
    _ledgerEntriesService.close();
  }
}
