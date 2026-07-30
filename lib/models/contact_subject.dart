import 'package:flutter/widgets.dart';

import '../localization/translations.dart';

/// Neutral subject categories offered in the Contact Us form's Subject
/// dropdown.
///
/// Kept as a small fixed list here (rather than fetched/configurable) since
/// no subject-category source exists elsewhere in the project yet.
enum ContactSubject {
  orderStatusInquiry,
  productAvailability,
  invoiceOrPayment,
  technicalSupport,
  generalInquiry,
  other,
}

extension ContactSubjectLabel on ContactSubject {
  String localizedLabel(BuildContext context) {
    switch (this) {
      case ContactSubject.orderStatusInquiry:
        return context.t('contactSubject.orderStatusInquiry');
      case ContactSubject.productAvailability:
        return context.t('contactSubject.productAvailability');
      case ContactSubject.invoiceOrPayment:
        return context.t('contactSubject.invoiceOrPayment');
      case ContactSubject.technicalSupport:
        return context.t('contactSubject.technicalSupport');
      case ContactSubject.generalInquiry:
        return context.t('contactSubject.generalInquiry');
      case ContactSubject.other:
        return context.t('contactSubject.other');
    }
  }
}
