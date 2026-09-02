// Fake in-memory LocalCustomerProfileStore for tests — no real secure
// storage platform channel is exercised.

import 'package:anc_fabrics/models/local_customer_profile.dart';
import 'package:anc_fabrics/services/local_customer_profile_store.dart';

class FakeLocalCustomerProfileStore implements LocalCustomerProfileStore {
  final Map<int, LocalCustomerProfile> _profiles = {};

  /// Every userId ever passed to [save], in call order.
  final List<int> savedUserIds = [];

  /// Every userId ever passed to [clear], in call order.
  final List<int> clearedUserIds = [];

  /// When set, thrown from [clear] instead of performing the clear.
  Object? clearError;

  /// Directly seeds a stored profile, bypassing [save], so tests can set up
  /// existing local data without it counting toward [savedUserIds].
  void seed(int userId, LocalCustomerProfile profile) =>
      _profiles[userId] = profile;

  @override
  Future<LocalCustomerProfile?> load(int userId) async => _profiles[userId];

  @override
  Future<void> save(int userId, LocalCustomerProfile profile) async {
    _profiles[userId] = profile;
    savedUserIds.add(userId);
  }

  @override
  Future<void> clear(int userId) async {
    clearedUserIds.add(userId);
    if (clearError != null) throw clearError!;
    _profiles.remove(userId);
  }
}
