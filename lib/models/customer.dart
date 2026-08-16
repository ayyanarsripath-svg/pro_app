class Customer {
  final String id;
  final String name;
  final String? phone;
  final String? phone2;
  final String? address;
  final String? email;
  final String? notes;
  final DateTime createdAt;

  Customer({
    required this.id,
    required this.name,
    this.phone,
    this.phone2,
    this.address,
    this.email,
    this.notes,
    required this.createdAt,
  });

  factory Customer.fromMap(Map<String, dynamic> m) => Customer(
        id: m['id'] as String,
        name: m['name'] as String,
        phone: m['phone'] as String?,
        phone2: m['phone2'] as String?,
        address: m['address'] as String?,
        email: m['email'] as String?,
        notes: m['notes'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'phone2': phone2,
        'address': address,
        'email': email,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
      };
}
