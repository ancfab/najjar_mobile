// Unit tests for the Contact Us form's reusable field validators: required
// text, email shape, and subject selection.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/contact_subject.dart';
import 'package:anc_fabrics/utils/contact_form_validators.dart';

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
    test('returns a required message for null input', () {
      expect(validateEmailField(null), 'Please enter your work email.');
    });

    test('returns a required message for empty input', () {
      expect(validateEmailField(''), 'Please enter your work email.');
    });

    test('returns a required message for whitespace-only input', () {
      expect(validateEmailField('   '), 'Please enter your work email.');
    });

    test('rejects a value missing @', () {
      expect(
        validateEmailField('jane.textile.co'),
        'Please enter a valid email address.',
      );
    });

    test('rejects a value missing the local part', () {
      expect(
        validateEmailField('@textile.co'),
        'Please enter a valid email address.',
      );
    });

    test('rejects a value missing the domain', () {
      expect(
        validateEmailField('jane@'),
        'Please enter a valid email address.',
      );
    });

    test('rejects a value missing a dot in the domain', () {
      expect(
        validateEmailField('jane@textile'),
        'Please enter a valid email address.',
      );
    });

    test('rejects a value containing internal whitespace', () {
      expect(
        validateEmailField('jane weaver@textile.co'),
        'Please enter a valid email address.',
      );
    });

    test('accepts an ordinary valid address', () {
      expect(validateEmailField('jane@textile.co'), isNull);
    });

    test('accepts a valid address with a subdomain and plus tag', () {
      expect(validateEmailField('jane+support@mail.textile.co'), isNull);
    });

    test('trims surrounding whitespace before validating', () {
      expect(validateEmailField('  jane@textile.co  '), isNull);
    });
  });

  group('validatePhoneField', () {
    test('returns a required message for null input', () {
      expect(validatePhoneField(null), 'Please enter your phone number.');
    });

    test('returns a required message for empty input', () {
      expect(validatePhoneField(''), 'Please enter your phone number.');
    });

    test('returns a required message for whitespace-only input', () {
      expect(validatePhoneField('   '), 'Please enter your phone number.');
    });

    test('rejects letters', () {
      expect(
        validatePhoneField('abc123'),
        'Please enter a valid phone number.',
      );
    });

    test('rejects too few digits', () {
      expect(validatePhoneField('12345'), 'Please enter a valid phone number.');
    });

    test('rejects too many digits', () {
      expect(
        validatePhoneField('1234567890123456'),
        'Please enter a valid phone number.',
      );
    });

    test('accepts a plain international number', () {
      expect(validatePhoneField('+9613123456'), isNull);
    });

    test(
      'accepts a number formatted with spaces, hyphens, and parentheses',
      () {
        expect(validatePhoneField('+1 (555) 902-3481'), isNull);
      },
    );

    test('trims surrounding whitespace before validating', () {
      expect(validatePhoneField('  +1 (555) 902-3481  '), isNull);
    });
  });

  group('validateSubjectField', () {
    test('returns a message when no subject is selected', () {
      expect(validateSubjectField(null), 'Please select a subject.');
    });

    test('returns null once a subject is selected', () {
      expect(validateSubjectField(ContactSubject.generalInquiry), isNull);
    });
  });
}
