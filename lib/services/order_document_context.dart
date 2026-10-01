import 'package:flutter/foundation.dart';

import 'auth_session_store.dart';
import 'customer_details_service.dart';
import 'local_customer_profile_store.dart';
import 'secure_auth_session_store.dart';

/// The customer identity and account figures a printed Sales Quotation
/// shows but the order lines themselves never carry: the signed-in
/// customer's phone and business address, and their current balance and
/// last payment.
class OrderDocumentContextData {
  const OrderDocumentContextData({
    this.customerAddress,
    this.customerPhone,
    this.countryIsoCode,
    this.balance,
    this.lastPaymentAmount,
    this.lastPaymentDate,
  });

  final String? customerAddress;
  final String? customerPhone;

  /// The session's ISO country code (e.g. `LB`), which the caller resolves
  /// to a localized country name — this layer never holds display text.
  final String? countryIsoCode;

  final double? balance;
  final double? lastPaymentAmount;
  final DateTime? lastPaymentDate;
}

/// The seam `OrderDetailScreen` reads that context through.
abstract interface class OrderDocumentContext {
  /// Resolves everything available; every field is independently optional,
  /// so one unavailable source never costs the user the whole document.
  Future<OrderDocumentContextData> load();
}

/// Default [OrderDocumentContext]: the stored session and local customer
/// profile for identity, plus a single live customer-details fetch for the
/// balance and last payment.
///
/// Every source is best-effort: a failure resolves that field to `null`
/// (the renderer then omits the matching row) rather than throwing, so a
/// customer with no connectivity to the customer-details endpoint still
/// gets a document of their order lines instead of an error. Nothing here
/// is cached — the customer-details contract requires a fresh fetch — so
/// this runs only when the user actually exports a document.
class SessionOrderDocumentContext implements OrderDocumentContext {
  const SessionOrderDocumentContext({
    this.sessionStore,
    this.profileStore,
    this.customerDetailsService,
  });

  final AuthSessionStore? sessionStore;
  final LocalCustomerProfileStore? profileStore;
  final CustomerDetailsService? customerDetailsService;

  @override
  Future<OrderDocumentContextData> load() async {
    final sessions = sessionStore ?? SecureAuthSessionStore();
    final profiles = profileStore ?? SecureLocalCustomerProfileStore();
    final details = customerDetailsService ?? CustomerDetailsService();

    String? phone;
    String? country;
    String? address;
    try {
      final session = await sessions.read();
      if (session != null) {
        phone = session.phone.trim().isEmpty ? null : session.phone;
        country = session.country.trim().isEmpty ? null : session.country;
        final profile = await profiles.load(session.userId);
        final storedAddress = profile?.businessAddress.trim();
        address = storedAddress == null || storedAddress.isEmpty
            ? null
            : storedAddress;
      }
    } catch (error) {
      debugPrint('Order document identity unavailable: $error');
    }

    double? balance;
    double? lastPaymentAmount;
    DateTime? lastPaymentDate;
    try {
      final snapshot = await details.fetchCustomerDetails();
      balance = snapshot.customerBalance;
      lastPaymentAmount = snapshot.lastPaymentAmount;
      lastPaymentDate = snapshot.lastPaymentDate;
    } catch (error) {
      // Includes SessionExpiredException: the session coordinator has
      // already taken over, and there is no document-specific error to
      // add on top of it.
      debugPrint('Order document account figures unavailable: $error');
    } finally {
      if (customerDetailsService == null) details.close();
    }

    return OrderDocumentContextData(
      customerAddress: address,
      customerPhone: phone,
      countryIsoCode: country,
      balance: balance,
      lastPaymentAmount: lastPaymentAmount,
      lastPaymentDate: lastPaymentDate,
    );
  }
}
