/// Defensive JSON readers - the UI must never crash on a missing/null field.
typedef Json = Map<String, dynamic>;

class J {
  static String str(Json? m, String k, [String d = '']) {
    final v = m?[k];
    return v == null ? d : v.toString();
  }

  static String? strN(Json? m, String k) {
    return m?[k]?.toString();
  }

  static int integer(Json? m, String k, [int d = 0]) {
    final v = m?[k];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? d;
  }

  static int? intN(Json? m, String k) {
    final v = m?[k];
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  static double? dblN(Json? m, String k) {
    final v = m?[k];
    if (v is num) return v.toDouble();
    return v == null ? null : double.tryParse('$v');
  }

  static bool boolean(Json? m, String k, [bool d = false]) {
    final v = m?[k];
    return v is bool ? v : d;
  }

  static bool? boolN(Json? m, String k) {
    final v = m?[k];
    return v is bool ? v : null;
  }

  static DateTime? dt(Json? m, String k) {
    final v = m?[k];
    return v is String ? DateTime.tryParse(v)?.toLocal() : null;
  }

  static Json map(Json? m, String k) {
    final v = m?[k];
    return v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
  }

  static Json? mapN(Json? m, String k) {
    final v = m?[k];
    return v is Map ? v.cast<String, dynamic>() : null;
  }

  static List<T> list<T>(Json? m, String k, T Function(Json) f) {
    final v = m?[k];
    if (v is! List) return <T>[];
    return v.whereType<Map>().map((e) => f(e.cast<String, dynamic>())).toList();
  }

  static List<String> strings(Json? m, String k) {
    final v = m?[k];
    return v is List ? v.map((e) => '$e').toList() : <String>[];
  }
}
