import 'package:intl/intl.dart';

/// Formats integer minor units (paise) without ever going through floating point arithmetic.
String formatMoney(int minor, {String currency = 'INR', bool free = false}) {
  if (free && minor == 0) return 'Free';
  final sym = currency == 'INR' ? '₹' : '$currency ';
  final neg = minor < 0;
  final abs = minor.abs();
  final whole = NumberFormat.decimalPattern('en_IN').format(abs ~/ 100);
  final frac = abs % 100;
  return '${neg ? '-' : ''}$sym$whole${frac == 0 ? '' : '.${frac.toString().padLeft(2, '0')}'}';
}

/// Rupees entered by the user ("15,000" / "15000.50") -> paise. Returns null if invalid.
int? parseMoneyToMinor(String input) {
  final s = input.replaceAll(RegExp(r'[,\s₹]'), '');
  if (s.isEmpty) return null;
  final m = RegExp(r'^(\d{1,9})(?:\.(\d{1,2}))?$').firstMatch(s);
  if (m == null) return null;
  final whole = int.parse(m.group(1)!);
  final frac = int.parse((m.group(2) ?? '').padRight(2, '0').substring(0, 2));
  return whole * 100 + frac;
}

String formatAge(int? months) {
  if (months == null) return 'Age n/a';
  if (months < 1) return '< 1 mo';
  if (months < 24) return '$months mo';
  final y = months ~/ 12;
  final m = months % 12;
  return m == 0 ? '$y yr' : '$y yr $m mo';
}

String formatDate(DateTime? d) => d == null ? '-' : DateFormat('d MMM y').format(d);
String formatDateTime(DateTime? d) => d == null ? '-' : DateFormat('d MMM y, h:mm a').format(d);

String timeAgo(DateTime? d, {DateTime? now}) {
  if (d == null) return '';
  final diff = (now ?? DateTime.now()).difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatDate(d);
}

String genderLabel(String g) => {'male': 'Male', 'female': 'Female'}[g] ?? 'Unknown';

String vaccinationLabel(String v) =>
    {
      'complete': 'Vaccinations: complete (seller-declared)',
      'partial': 'Vaccinations: partial (seller-declared)',
      'none': 'Not vaccinated (seller-declared)',
    }[v] ??
    'Vaccination not disclosed';

String vaccinationShort(String v) =>
    {'complete': 'Vaccinated', 'partial': 'Partly vaccinated', 'none': 'Unvaccinated'}[v] ?? '';

String titleCase(String s) =>
    s.isEmpty ? s : s.split('_').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

const indianStates = [
  'Andhra Pradesh',
  'Arunachal Pradesh',
  'Assam',
  'Bihar',
  'Chhattisgarh',
  'Goa',
  'Gujarat',
  'Haryana',
  'Himachal Pradesh',
  'Jharkhand',
  'Karnataka',
  'Kerala',
  'Madhya Pradesh',
  'Maharashtra',
  'Manipur',
  'Meghalaya',
  'Mizoram',
  'Nagaland',
  'Odisha',
  'Punjab',
  'Rajasthan',
  'Sikkim',
  'Tamil Nadu',
  'Telangana',
  'Tripura',
  'Uttar Pradesh',
  'Uttarakhand',
  'West Bengal',
  'Andaman and Nicobar Islands',
  'Chandigarh',
  'Dadra and Nagar Haveli and Daman and Diu',
  'Delhi',
  'Jammu and Kashmir',
  'Ladakh',
  'Lakshadweep',
  'Puducherry',
];
