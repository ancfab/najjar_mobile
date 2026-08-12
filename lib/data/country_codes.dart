import '../models/country_code.dart';

const CountryCode kDefaultCountryCode = CountryCode(
  name: 'United Arab Emirates',
  isoCode: 'AE',
  dialCode: '+971',
  flag: '🇦🇪',
);

// Supported regional countries for ANC authentication and phone selection.
const List<CountryCode> kCountryCodes = [
  CountryCode(name: 'Lebanon', isoCode: 'LB', dialCode: '+961', flag: '🇱🇧'),
  CountryCode(name: 'Iraq', isoCode: 'IQ', dialCode: '+964', flag: '🇮🇶'),
  // `flag` is unused for Syria: CountryCodePicker renders the current
  // (green-white-black, three red stars) design via SyriaFlag instead, since
  // the 🇸🇾 emoji glyph is platform/font-supplied and can still show the
  // outdated pre-2024 flag on some devices. Kept here only so this entry has
  // the same shape as every other CountryCode.
  CountryCode(name: 'Syria', isoCode: 'SY', dialCode: '+963', flag: '🇸🇾'),
  CountryCode(name: 'Oman', isoCode: 'OM', dialCode: '+968', flag: '🇴🇲'),
  kDefaultCountryCode,
];
