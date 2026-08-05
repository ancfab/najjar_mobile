/// Compares two Business Central `Document_No` values so that embedded
/// numeric runs are compared by numeric magnitude rather than character-by-
/// character (e.g. `"INV-9"` sorts before `"INV-10"`, where plain
/// [String.compareTo] would put them the other way around), while non-digit
/// runs still compare as plain strings.
///
/// This is a general-purpose "natural sort" ordering, not a parser for any
/// specific invoice-numbering scheme — it makes no assumption about prefix
/// text, digit count, or separator characters, so it applies safely to any
/// consistently-increasing `Document_No` format without inventing business
/// meaning for the value (e.g. it never strips a prefix or treats part of
/// the string as a date). Two values that differ only in leading zeros
/// within an otherwise-identical numeric run (e.g. `"INV-007"` vs.
/// `"INV-7"`) compare as equal, since both represent the same numeric
/// magnitude in the same position.
///
/// Returns negative if [a] sorts before [b], positive if after, zero if
/// equal under this ordering.
int compareDocumentNoNatural(String a, String b) {
  final segmentsA = _splitIntoSegments(a);
  final segmentsB = _splitIntoSegments(b);
  final commonLength = segmentsA.length < segmentsB.length
      ? segmentsA.length
      : segmentsB.length;

  for (var i = 0; i < commonLength; i++) {
    final segA = segmentsA[i];
    final segB = segmentsB[i];
    final comparison = (segA.isNumeric && segB.isNumeric)
        ? BigInt.parse(segA.text).compareTo(BigInt.parse(segB.text))
        : segA.text.compareTo(segB.text);
    if (comparison != 0) return comparison;
  }
  return segmentsA.length.compareTo(segmentsB.length);
}

class _Segment {
  const _Segment(this.text, this.isNumeric);
  final String text;
  final bool isNumeric;
}

final RegExp _segmentPattern = RegExp(r'\d+|\D+');
final RegExp _digitsOnlyPattern = RegExp(r'^\d+$');

List<_Segment> _splitIntoSegments(String value) {
  return [
    for (final match in _segmentPattern.allMatches(value))
      _Segment(match.group(0)!, _digitsOnlyPattern.hasMatch(match.group(0)!)),
  ];
}
