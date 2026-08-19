class Asset {
  final String? id;
  final String name;
  final String? type;
  final String? assetCategory;
  final String? serialNumber;
  final String? location;
  final String status;
  final String? branchId;
  final Map<String, dynamic>? branch;
  final String? notes;
  final String? assetPhoto;
  final Map<String, dynamic>? assignedTo;
  final Map<String, dynamic>? assetTypeId;
  final DateTime? purchaseDate;
  final DateTime? warrantyExpiry;

  Asset({
    this.id,
    required this.name,
    this.type,
    this.assetCategory,
    this.serialNumber,
    this.location,
    required this.status,
    this.branchId,
    this.branch,
    this.notes,
    this.assetPhoto,
    this.assignedTo,
    this.assetTypeId,
    this.purchaseDate,
    this.warrantyExpiry,
  });

  factory Asset.fromJson(Map<String, dynamic> json) {
    return Asset(
      id: json['_id'] ?? json['id'],
      name: json['name'] ?? '',
      type: json['type'] ?? json['assetTypeId']?['name'],
      assetCategory: json['assetCategory'] ?? json['assetTypeId']?['name'],
      serialNumber: json['serialNumber'],
      location: json['location'] ?? '',
      status: json['status'] ?? 'Working',
      branchId: json['branchId']?['_id'] ?? json['branchId'],
      branch: json['branchId'] is Map ? json['branchId'] : null,
      notes: json['notes'],
      assetPhoto: json['assetPhoto'] ?? json['image'], // Handle both fields
      assignedTo: json['assignedTo'] is Map ? json['assignedTo'] : null,
      assetTypeId: json['assetTypeId'] is Map ? json['assetTypeId'] : null,
      purchaseDate: _parseDate(json['purchaseDate']),
      warrantyExpiry: _parseDate(json['warrantyExpiry']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  /// Keywords that mark an asset as a software licence / subscription rather
  /// than a physical (hardware) asset. Matched against [type] and
  /// [assetCategory] case-insensitively.
  static const List<String> _softwareKeywords = [
    'software',
    'licen', // licence / license
    'subscription',
    'saas',
    'cloud',
    'application',
    'app ',
    'antivirus',
    'os ',
    'operating system',
    'plan',
  ];

  /// True when this asset represents a software licence/subscription.
  bool get isSoftware {
    final haystack = '${type ?? ''} ${assetCategory ?? ''} $name'.toLowerCase();
    return _softwareKeywords.any(haystack.contains);
  }

  /// Whole days until [warrantyExpiry] (used as the renewal date for
  /// software licences). Null when no expiry is known.
  int? get daysToRenew {
    if (warrantyExpiry == null) return null;
    final now = DateTime.now();
    return warrantyExpiry!
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
  }

  String get branchName {
    if (branch != null) {
      final branchName = branch!['branchName'] ?? '';
      final branchCode = branch!['branchCode'] ?? '';
      if (branchCode.isNotEmpty) {
        return '$branchName ($branchCode)';
      }
      return branchName;
    }
    return '';
  }
}
