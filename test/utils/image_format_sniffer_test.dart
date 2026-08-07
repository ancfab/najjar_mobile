// Unit tests for image_format_sniffer.dart's magic-byte format detection —
// covers each supported format's signature, rejection of non-matching
// bytes, and the two combined convenience checks
// (hasSupportedAvatarSourceSignature / hasSupportedAvatarUploadSignature).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/utils/image_format_sniffer.dart';

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

void main() {
  group('isJpeg', () {
    test('recognizes the JPEG signature', () {
      expect(_bytes([0xFF, 0xD8, 0xFF, 0xE0]), predicate(isJpeg));
    });

    test('rejects a non-JPEG signature', () {
      expect(isJpeg(_bytes([0x00, 0x01, 0x02])), isFalse);
    });

    test('rejects bytes shorter than the signature', () {
      expect(isJpeg(_bytes([0xFF, 0xD8])), isFalse);
    });
  });

  group('isPng', () {
    test('recognizes the PNG signature', () {
      expect(
        isPng(_bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])),
        isTrue,
      );
    });

    test('rejects a non-PNG signature', () {
      expect(isPng(_bytes([0x00, 0x01, 0x02, 0x03])), isFalse);
    });

    test('rejects bytes shorter than the signature', () {
      expect(isPng(_bytes([0x89, 0x50])), isFalse);
    });
  });

  group('isWebp', () {
    Uint8List webpBytes() => _bytes([
      0x52, 0x49, 0x46, 0x46, // "RIFF"
      0x00, 0x00, 0x00, 0x00, // size (unused by the sniffer)
      0x57, 0x45, 0x42, 0x50, // "WEBP"
    ]);

    test('recognizes the WEBP signature', () {
      expect(isWebp(webpBytes()), isTrue);
    });

    test('rejects a RIFF container that is not WEBP', () {
      final bytes = webpBytes();
      bytes[8] = 0x41; // corrupt the "WEBP" fourCC
      expect(isWebp(bytes), isFalse);
    });

    test('rejects bytes shorter than the signature', () {
      expect(isWebp(_bytes([0x52, 0x49, 0x46, 0x46])), isFalse);
    });
  });

  group('isHeic', () {
    Uint8List heicBytes() => _bytes([
      0x00, 0x00, 0x00, 0x18, // box size (unused by the sniffer)
      0x66, 0x74, 0x79, 0x70, // "ftyp"
      0x68, 0x65, 0x69, 0x63, // "heic" brand
    ]);

    test('recognizes the HEIC ftyp signature', () {
      expect(isHeic(heicBytes()), isTrue);
    });

    test('rejects bytes without an ftyp box', () {
      expect(isHeic(_bytes(List.filled(12, 0x00))), isFalse);
    });

    test('rejects bytes shorter than the signature', () {
      expect(isHeic(_bytes([0x00, 0x00, 0x00, 0x18])), isFalse);
    });
  });

  group('hasSupportedAvatarSourceSignature (pre-crop: jpg/png/webp/heic)', () {
    test('accepts JPEG', () {
      expect(
        hasSupportedAvatarSourceSignature(_bytes([0xFF, 0xD8, 0xFF])),
        isTrue,
      );
    });

    test('accepts HEIC (the picker/cropper source-only format)', () {
      final bytes = _bytes([
        0x00,
        0x00,
        0x00,
        0x18,
        0x66,
        0x74,
        0x79,
        0x70,
        0x68,
        0x65,
        0x69,
        0x63,
      ]);
      expect(hasSupportedAvatarSourceSignature(bytes), isTrue);
    });

    test('rejects an unrecognized format', () {
      expect(
        hasSupportedAvatarSourceSignature(_bytes(List.filled(16, 0x00))),
        isFalse,
      );
    });
  });

  group('hasSupportedAvatarUploadSignature (post-crop: jpg/png/webp only)', () {
    test('accepts JPEG', () {
      expect(
        hasSupportedAvatarUploadSignature(_bytes([0xFF, 0xD8, 0xFF])),
        isTrue,
      );
    });

    test('accepts PNG', () {
      expect(
        hasSupportedAvatarUploadSignature(
          _bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        ),
        isTrue,
      );
    });

    test('accepts WEBP', () {
      final bytes = _bytes([
        0x52,
        0x49,
        0x46,
        0x46,
        0x00,
        0x00,
        0x00,
        0x00,
        0x57,
        0x45,
        0x42,
        0x50,
      ]);
      expect(hasSupportedAvatarUploadSignature(bytes), isTrue);
    });

    test(
      'rejects HEIC — the ANC API avatar-upload endpoint never accepts it',
      () {
        final bytes = _bytes([
          0x00,
          0x00,
          0x00,
          0x18,
          0x66,
          0x74,
          0x79,
          0x70,
          0x68,
          0x65,
          0x69,
          0x63,
        ]);
        expect(hasSupportedAvatarUploadSignature(bytes), isFalse);
      },
    );

    test('rejects an unrecognized format', () {
      expect(
        hasSupportedAvatarUploadSignature(_bytes(List.filled(16, 0x00))),
        isFalse,
      );
    });
  });
}
