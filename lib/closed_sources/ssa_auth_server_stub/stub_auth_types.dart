// Open stub: identity types compatible with db/auth_identities.toml (no codegen).

enum AuthIdentityType {
  signedFingerprint,
  password,
}

enum AuthKeyType {
  ed25519,
  rsa,
}

class AuthIdentity {
  final String identityName;
  final List<String> roles;
  final AuthIdentityType type;
  final String authenticationMaterial;

  AuthIdentity({
    required this.identityName,
    required this.roles,
    required this.type,
    required this.authenticationMaterial,
  });

  AuthIdentity.signedFingerprint({
    required this.identityName,
    required this.roles,
    required this.authenticationMaterial,
  }) : type = AuthIdentityType.signedFingerprint;

  AuthIdentity.password({
    required this.identityName,
    required this.roles,
    required this.authenticationMaterial,
  }) : type = AuthIdentityType.password;

  factory AuthIdentity.fromToml(Map<String, dynamic> json) {
    return AuthIdentity(
      identityName: json["identityName"] as String,
      roles: (json["roles"] as List<dynamic>).map((e) => e as String).toList(),
      type: AuthIdentityType.values.firstWhere(
        (v) => v.name == json["type"] as String,
        orElse: () => AuthIdentityType.signedFingerprint,
      ),
      authenticationMaterial: json["authenticationMaterial"] as String,
    );
  }

  Map<String, dynamic> toToml() {
    return {
      "identityName": identityName,
      "roles": roles,
      "type": type.name,
      "authenticationMaterial": authenticationMaterial,
    };
  }

  AuthIdentity copy() => AuthIdentity(
    identityName: identityName,
    roles: [...roles],
    type: type,
    authenticationMaterial: authenticationMaterial,
  );

  @override
  String toString() {
    return "AuthIdentity(identityName: $identityName, roles: $roles, type: $type, authenticationMaterial: ${authenticationMaterial.length} chars)";
  }
}
