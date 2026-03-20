class ReferrerBlockConfig {
  const ReferrerBlockConfig({required this.door, required this.ilve});

  factory ReferrerBlockConfig.fromJson(Map<String, dynamic> json) {
    return ReferrerBlockConfig(
      door: _readInt(json['door']) ?? 0,
      ilve: _readStringList(json['ilve']),
    );
  }

  final int door;
  final List<String> ilve;

  bool get isEnabled => door == 1;

  bool shouldBlock(String? referrer) {
    if (!isEnabled) {
      return false;
    }
    if (referrer == null || referrer.isEmpty) {
      return true;
    }

    final raw = referrer.toLowerCase();
    final decoded = Uri.decodeFull(referrer).toLowerCase();
    for (final keyword in ilve) {
      final normalizedKeyword = keyword.toLowerCase();
      if (raw.contains(normalizedKeyword) ||
          decoded.contains(normalizedKeyword)) {
        return false;
      }
    }
    return true;
  }

  String get logSummary => 'door=$door ilve=$ilve';
}

int? _readInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

List<String> _readStringList(dynamic value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.map((item) => item.toString()).toList(growable: false);
}
