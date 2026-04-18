/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:json_annotation/json_annotation.dart';

part 'auth_identity.g.dart';

enum AuthIdentityType {
  signedFingerprint,
  password,
}

enum AuthKeyType {
  ed25519,
  rsa,
}

@JsonSerializable()
class AuthIdentity {
  /// The name of the identity.
  final String identityName;
  /// The identity's roles. See [SSAAuthServer.knownRoles].
  final List<String> roles;
  /// The type of authentication material used to authenticate the identity.
  final AuthIdentityType type;
  /// The authentication material used to authenticate the requests for this
  /// identity, i.e. a public key for a signed fingerprint or a hashed password.
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

  factory AuthIdentity.fromToml(Map<String, dynamic> json) => _$AuthIdentityFromJson(json);
  Map<String, dynamic> toToml() => _$AuthIdentityToJson(this);


  AuthIdentity copy() => AuthIdentity(
    identityName: identityName,
    roles: roles,
    type: type,
    authenticationMaterial: authenticationMaterial,
  );

  @override
  String toString() => 'AuthIdentity(identityName: $identityName, roles: $roles, type: $type, authenticationMaterial: $authenticationMaterial)';
}