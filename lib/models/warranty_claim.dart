class WarrantyClaim {
  final String id;
  final String claimType; // service | second_hand | accessory
  final String referenceId;
  final DateTime claimDate;
  final String? description;
  final String? resolution;
  final double cost;
  final String status; // Open | Resolved | Rejected
  final DateTime createdAt;

  WarrantyClaim({
    required this.id,
    required this.claimType,
    required this.referenceId,
    required this.claimDate,
    this.description,
    this.resolution,
    this.cost = 0,
    this.status = 'Open',
    required this.createdAt,
  });

  factory WarrantyClaim.fromMap(Map<String, dynamic> m) => WarrantyClaim(
        id: m['id'] as String,
        claimType: m['claim_type'] as String,
        referenceId: m['reference_id'] as String,
        claimDate: DateTime.parse(m['claim_date'] as String),
        description: m['description'] as String?,
        resolution: m['resolution'] as String?,
        cost: (m['cost'] as num?)?.toDouble() ?? 0,
        status: m['status'] as String? ?? 'Open',
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'claim_type': claimType,
        'reference_id': referenceId,
        'claim_date': claimDate.toIso8601String(),
        'description': description,
        'resolution': resolution,
        'cost': cost,
        'status': status,
        'created_at': createdAt.toIso8601String(),
      };
}
