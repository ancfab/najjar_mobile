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
  String get label {
    switch (this) {
      case ContactSubject.orderStatusInquiry:
        return 'Order Status Inquiry';
      case ContactSubject.productAvailability:
        return 'Product Availability';
      case ContactSubject.invoiceOrPayment:
        return 'Invoice or Payment';
      case ContactSubject.technicalSupport:
        return 'Technical Support';
      case ContactSubject.generalInquiry:
        return 'General Inquiry';
      case ContactSubject.other:
        return 'Other';
    }
  }
}
