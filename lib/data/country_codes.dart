import '../models/country_code.dart';

const CountryCode kDefaultCountryCode = CountryCode(
  name: 'United Arab Emirates',
  isoCode: 'AE',
  dialCode: '+971',
  flag: '🇦🇪',
);

// TODO: Confirm whether the final list should include all countries or only
// project regional countries.
const List<CountryCode> kCountryCodes = [
  CountryCode(name: 'Lebanon', isoCode: 'LB', dialCode: '+961', flag: '🇱🇧'),
  CountryCode(name: 'Iraq', isoCode: 'IQ', dialCode: '+964', flag: '🇮🇶'),
  CountryCode(name: 'Syria', isoCode: 'SY', dialCode: '+963', flag: '🇸🇾'),
  CountryCode(name: 'Oman', isoCode: 'OM', dialCode: '+968', flag: '🇴🇲'),
  kDefaultCountryCode,
];
