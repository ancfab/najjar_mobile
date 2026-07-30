// Unit tests for the Contact Us form's reusable field validators: required
// text, email shape, and subject selection.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/contact_subject.dart';
import 'package:anc_fabrics/utils/contact_form_validators.dart';

import '../helpers/localized_test_context.dart';

void main() {
  group('validateRequiredField', () {
    test('returns the message for null input', () {
      expect(validateRequiredField(null, 'Required.'), 'Required.');
    });

    test('returns the message for empty input', () {
      expect(validateRequiredField('', 'Required.'), 'Required.');
    });

    test('returns the message for whitespace-only input', () {
      expect(validateRequiredField('   ', 'Required.'), 'Required.');
    });

    test('returns null for non-blank input', () {
      expect(validateRequiredField('Jane Weaver', 'Required.'), isNull);
    });

    test('returns null for input with meaningful surrounding whitespace', () {
      expect(validateRequiredField('  Jane Weaver  ', 'Required.'), isNull);
    });
  });

  group('validateEmailField', () {
    testWidgets('returns a required message for null input', (tester) async {
      final context = await pumpLocalizedContext(tester);
      expect(
        validateEmailField(context, null),
        'Please enter your work email.',
      );
    });

    testWidgets('returns a required message for empty input', (tester) async {
      final context = await pumpLocalizedContext(tester);
      expect(validateEmailField(context, ''), 'Please enter your work email.');
    });

    testWidgets('returns a required message for whitespace-only input', (
      tester,
    ) async {
      final context = await pumpLocalizedContext(tester);
      expect(
        validateEmailField(context, '   '),
        'Please enter your work email.',
      );
    });

    testWidgets('rejects a value missing @', (tester) async {
      final context = await pumpLocalizedContext(tester);
      expect(
        validateEmailField(context, 'jane.textile.co'),
        'Please enter a valid email address.',
      );
    });

    testWidgets('rejects a value missing the local part', (tester) async {
      final context = await pumpLocalizedContext(tester);
      expect(
        validateEmailField(context, '@textile.co'),
        'Please enter a valid email address.',
      );
    });

    testWidgets('rejects a value missing the domain', (tester) async {
      final context = await pumpLocalizedContext(tester);
      expect(
        validateEmailField(context, 'jane@'),
        'Please enter a valid email address.',
      );
    });

    testWidgets('rejects a value missing a dot in the domain', (tester) async {
      final context = await pumpLocalizedContext(tester);
      expect(
        validateEmailField(context, 'jane@textile'),
        'Please enter a valid email address.',
      );
    });

    testWidgets('rejects a value containing internal whitespace', (
      tester,
    ) async {
      final context = await pumpLocalizedContext(tester);
      expect(
        validateEmailField(context, 'jane weaver@textile.co'),
        'Please enter a valid email address.',
      );
    });

    testWidgets('accepts an ordinary valid address', (tester) async {
      final context = await pumpLocalizedContext(tester);
      expect(validateEmailField(context, 'jane@textile.co'), isNull);
    });

    testWidgets('accepts a valid address with a subdomain and plus tag', (
      tester,
    ) async {
      final context = await pumpLocalizedContext(tester);
      expect(
        validateEmailField(context, 'jane+support@mail.textile.co'),
        isNull,
      );
    });

    testWidgets('trims surrounding whitespace before validating', (
      tester,
    ) async {
      final context = await pumpLocalizedContext(tester);
      expect(validateEmailField(context, '  jane@textile.co  '), isNull);
    });
  });

  group('validatePhoneField', () {
    testWidgets('returns a required message for null input', (tester) async {
      final context = await pumpLocalizedContext(tester);
      expect(
        validatePhoneField(context, null),
        'Please enter your phone number.',
      );
    });

    testWidgets('returns a required message for empty input', (tester) async {
      final context = await pumpLocalizedContext(tester);
      expect(
        validatePhoneField(context, ''),
        'Please enter your phone number.',
      );
    });

    testWidgets('returns a required message for whitespace-only input', (
      tester,
    ) async {
      final context = await pumpLocalizedContext(tester);
      expect(
        validatePhoneField(context, '   '),
        'Please enter your phone number.',
      );
    });

    testWidgets('rejects letters', (tester) async {
      final context = await pumpLocalizedContext(tester);
      expect(
        validatePhoneField(context, 'abc123'),
        'Please enter a valid phone number.',
      );
    });

    testWidgets('rejects too few digits', (tester) async {
      final context = await pumpLocalizedContext(tester);
      expect(
        validatePhoneField(context, '12345'),
        'Please enter a valid phone number.',
      );
    });

    testWidgets('rejects too many digits', (tester) async {
      final context = await pumpLocalizedContext(tester);
      expect(
        validatePhoneField(context, '1234567890123456'),
        'Please enter a valid phone number.',
      );
    });

    testWidgets('accepts a plain international number', (tester) async {
      final context = await pumpLocalizedContext(tester);
      expect(validatePhoneField(context, '+9613123456'), isNull);
    });

    testWidgets(
      'accepts a number formatted with spaces, hyphens, and parentheses',
      (tester) async {
        final context = await pumpLocalizedContext(tester);
        expect(validatePhoneField(context, '+1 (555) 902-3481'), isNull);
      },
    );

    testWidgets('trims surrounding whitespace before validating', (
      tester,
    ) async {
      final context = await pumpLocalizedContext(tester);
      expect(validatePhoneField(context, '  +1 (555) 902-3481  '), isNull);
    });
  });

  group('validateSubjectField', () {
    testWidgets('returns a message when no subject is selected', (
      tester,
    ) async {
      final context = await pumpLocalizedContext(tester);
      expect(validateSubjectField(context, null), 'Please select a subject.');
    });

    testWidgets('returns null once a subject is selected', (tester) async {
      final context = await pumpLocalizedContext(tester);
      expect(
        validateSubjectField(context, ContactSubject.generalInquiry),
        isNull,
      );
    });
  });
}
