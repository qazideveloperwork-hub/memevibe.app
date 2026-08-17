class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.isPro,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'] as int,
    name: json['name'] as String,
    email: json['email'] as String,
    isPro: json['is_pro'] as bool? ?? false,
  );

  final int id;
  final String name;
  final String email;
  final bool isPro;
}
