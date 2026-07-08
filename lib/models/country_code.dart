/// A selectable country dial-code option.
///
/// Flags are rendered as Unicode flag emoji, so no image assets or extra
/// packages are required to display them.
class CountryCode {
  const CountryCode({
    required this.name,
    required this.isoCode,
    required this.dialCode,
    required this.flag,
  });

  final String name;
  final String isoCode;
  final String dialCode;
  final String flag;
}
