class User {
  final int? id;
  final String name;
  final String email;
  final String phone;
  final String role;
  final String? facultyCode;
  final String? facultyName;

  User({
    this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    this.facultyCode,
    this.facultyName,
  });

  factory User.fromJson(Map<String, dynamic> json, String role) {
    return User(
      id: json['id'] is String ? int.tryParse(json['id']) : json['id'],
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      role: role,
      facultyCode: json['faculty']?['code'],
      facultyName: json['faculty']?['name'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'role': role,
      'faculty': facultyCode != null
          ? {'code': facultyCode, 'name': facultyName}
          : null,
    };
  }
}
