/// Coerces [v] to a [String], returning [fallback] when it has no sane
/// textual representation. Never throws.
String asString(dynamic v, [String fallback = '']) {
  if (v is String) return v;
  if (v is num) return v.toString();
  if (v is bool) return v.toString();
  return fallback;
}

/// Coerces [v] to an [int], accepting numeric strings and doubles
/// (`asInt('12') == 12`, `asInt(3.7) == 3`). Never throws.
int asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is double) return v.isFinite ? v.toInt() : fallback;
  if (v is bool) return v ? 1 : 0;
  if (v is String) {
    final String s = v.trim();
    final int? parsed = int.tryParse(s);
    if (parsed != null) return parsed;
    final double? asNum = double.tryParse(s);
    if (asNum != null && asNum.isFinite) return asNum.toInt();
  }
  return fallback;
}

/// Coerces [v] to a [double], accepting numeric strings
/// (`asDouble('1.5') == 1.5`). Non-finite values fall back. Never throws.
double asDouble(dynamic v, [double fallback = 0]) {
  if (v is double) return v.isFinite ? v : fallback;
  if (v is int) return v.toDouble();
  if (v is bool) return v ? 1.0 : 0.0;
  if (v is String) {
    final double? parsed = double.tryParse(v.trim());
    if (parsed != null && parsed.isFinite) return parsed;
  }
  return fallback;
}

/// Coerces [v] to a [bool], accepting `'true'`/`'false'`, `'yes'`/`'no'`,
/// `'1'`/`'0'` and numbers. Never throws.
bool asBool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final String s = v.trim().toLowerCase();
    if (s == 'true' || s == 'yes' || s == '1') return true;
    if (s == 'false' || s == 'no' || s == '0') return false;
  }
  return fallback;
}

/// Returns [v] as a list, or an empty list when it is not one. Never throws.
List<dynamic> asList(dynamic v) {
  if (v is List) return v;
  return const <dynamic>[];
}

/// Returns [v] as a string-keyed map, converting non-string keys with
/// `toString()`. Returns an empty map for anything else. Never throws.
Map<String, dynamic> asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) {
    final Map<String, dynamic> out = <String, dynamic>{};
    for (final MapEntry<dynamic, dynamic> entry in v.entries) {
      out[asString(entry.key)] = entry.value;
    }
    return out;
  }
  return <String, dynamic>{};
}

/// Returns [v] as a list of strings, coercing every element. Never throws.
List<String> asStringList(dynamic v) {
  return <String>[for (final dynamic e in asList(v)) asString(e)];
}

/// Returns [v] as a `Map<String, int>`, coercing every key and value.
/// Never throws.
Map<String, int> asIntMap(dynamic v) {
  final Map<String, dynamic> raw = asMap(v);
  final Map<String, int> out = <String, int>{};
  for (final MapEntry<String, dynamic> entry in raw.entries) {
    out[entry.key] = asInt(entry.value);
  }
  return out;
}

/// Resolves [v] against [values] by an explicit wire name, returning `null`
/// when there is no match.
///
/// Used by the enums whose serialized form deliberately differs from their
/// Dart identifier (`GamePhase.wordSelection` travels as `word_selection`).
/// Never throws.
T? asWireEnum<T extends Enum>(
  List<T> values,
  dynamic v,
  String Function(T) wireOf,
) {
  if (v is T) return v;
  if (v is! String) return null;
  final String name = v.trim();
  for (final T value in values) {
    if (wireOf(value) == name) return value;
  }
  final String lower = name.toLowerCase();
  for (final T value in values) {
    if (wireOf(value).toLowerCase() == lower) return value;
  }
  return null;
}

/// Resolves [v] against [values] by enum `name` (case-insensitively) or by
/// index, returning `null` when there is no match. Never throws.
T? asEnum<T extends Enum>(List<T> values, dynamic v) {
  if (v is T) return v;
  if (v is int) {
    return v >= 0 && v < values.length ? values[v] : null;
  }
  if (v is! String) return null;
  final String name = v.trim();
  for (final T value in values) {
    if (value.name == name) return value;
  }
  final String lower = name.toLowerCase();
  for (final T value in values) {
    if (value.name.toLowerCase() == lower) return value;
  }
  return null;
}
