/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';
import 'dart:typed_data';

const rsaKeyType = "ssh-rsa";
const ed25519KeyType = "ssh-ed25519";

/// Represents a simple RSA public key that consists of modulus and exponent.
class OpenSSHRsaPublicKey {
  final List<int> modulus;
  final List<int> publicExponent;

  const OpenSSHRsaPublicKey({
    required this.modulus,
    required this.publicExponent,
  });
}

class OpenSSHEd25519PublicKey {
  final Uint8List publicKey;

  const OpenSSHEd25519PublicKey({
    required this.publicKey,
  });
}


/// Represents the full set of RSA key components that OpenSSH exposes.
class OpenSSHRsaKeyPair {
  final List<int> modulus;
  final List<int> publicExponent;
  final List<int> privateExponent;
  final List<int> iqmp;
  final List<int> prime1;
  final List<int> prime2;

  const OpenSSHRsaKeyPair({
    required this.modulus,
    required this.publicExponent,
    required this.privateExponent,
    required this.iqmp,
    required this.prime1,
    required this.prime2,
  });
}

/// Represents the ed25519 key material stored in an OpenSSH key file.
class OpenSSHEd25519KeyPair {
  final Uint8List publicKey;
  final Uint8List privateKey;

  const OpenSSHEd25519KeyPair({
    required this.publicKey,
    required this.privateKey,
  });
}

/// Parses a base64-encoded SSH RSA public key blob that follows the OpenSSH wire format.
(List<int> e, List<int> n) parseOpenSSHBase64RsaPublicKey(String keyBase64) {
  final normalized = keyBase64.replaceAll(RegExp(r'\s+'), '');
  final raw = Uint8List.fromList(base64.decode(normalized));
  final reader = _OpenSSHReader(raw);

  final keyType = reader.readString();
  if (keyType != rsaKeyType) {
    throw FormatException("Expected ssh-rsa public key, got $keyType");
  }

  final eBytes = reader.readMpInt();
  final nBytes = reader.readMpInt();

  return (eBytes, nBytes);
}

OpenSSHEd25519KeyPair _readOpenSshEd25519PrivateKey(_OpenSSHReader reader) {
  final publicKey = reader.readLengthPrefixedBytes();
  final privateKey = reader.readLengthPrefixedBytes();
  reader.readString(); // comment

  return OpenSSHEd25519KeyPair(
    publicKey: Uint8List.fromList(publicKey),
    privateKey: Uint8List.fromList(privateKey.sublist(0, 32)),
  );
}

/// Parses a public key file and returns the OpenSSH key type with its payload.
(String keyType, Object data) parsePublicKeyFile(String keyText) {
  final trimmed = keyText.trim();
  if (trimmed.isEmpty) {
    throw FormatException("Public key text is empty.");
  }

  if (trimmed.startsWith("$rsaKeyType ")) {
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length < 2) {
      throw FormatException("ssh-rsa public key is missing a base64 blob.");
    }
    final (e, n) = parseOpenSSHBase64RsaPublicKey(parts[1]);
    return (rsaKeyType, OpenSSHRsaPublicKey(modulus: n, publicExponent: e));
  }

  if (trimmed.startsWith("$ed25519KeyType ")) {
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length < 2) {
      throw FormatException("ssh-ed25519 public key is missing a base64 blob.");
    }
    final reader = _readerFromBase64(parts[1]);
    final keyType = reader.readString();
    if (keyType != ed25519KeyType) {
      throw FormatException("Expected ssh-ed25519 public key, got $keyType");
    }
    return (ed25519KeyType, OpenSSHEd25519PublicKey(publicKey: Uint8List.fromList(reader.readLengthPrefixedBytes())));
  }

  if (_hasPemBlock(trimmed, "OPENSSH PUBLIC KEY")) {
    final blob = _decodePemBlock(trimmed, "OPENSSH PUBLIC KEY");
    return (rsaKeyType, _parseOpenSSHPublicKeyBlob(blob));
  }

  if (_hasPemBlock(trimmed, "RSA PUBLIC KEY")) {
    return (rsaKeyType, parsePemRsaPublicKey(trimmed));
  }

  throw FormatException("Unsupported public key format.");
}

/// Parses a private key file and returns the OpenSSH key type with its payload.
(String keyType, Object data) parsePrivateKeyFile(String keyText) {
  final trimmed = keyText.trim();
  if (trimmed.isEmpty) {
    throw FormatException("Private key text is empty.");
  }

  if (_hasPemBlock(trimmed, "OPENSSH PRIVATE KEY")) {
    final privateBlock = _extractOpenSSHPrivateBlock(trimmed);
    return _parseOpenSSHPrivateKeyBlock(privateBlock);
  }

  if (_hasPemBlock(trimmed, "RSA PRIVATE KEY")) {
    return (rsaKeyType, parsePemRsaPrivateKey(trimmed));
  }

  throw FormatException("Unsupported private key format.");
}

/// Parses an OpenSSH RSA private key in the new PEM format and returns every RSA component.
OpenSSHRsaKeyPair parseOpenSSHRsaPrivateKey(String keyText) {
  final privateBlock = _extractOpenSSHPrivateBlock(keyText);
  final (keyType, data) = _parseOpenSSHPrivateKeyBlock(privateBlock);
  if (keyType != rsaKeyType) {
    throw FormatException("Expected ssh-rsa key, got $keyType.");
  }

  return data as OpenSSHRsaKeyPair;
}

/// Parses an OpenSSH ed25519 private key.
OpenSSHEd25519KeyPair parseOpenSSHEd25519PrivateKey(String keyText) {
  final privateBlock = _extractOpenSSHPrivateBlock(keyText);
  final (keyType, data) = _parseOpenSSHPrivateKeyBlock(privateBlock);
  if (keyType != ed25519KeyType) {
    throw FormatException("Expected ssh-ed25519 key, got $keyType.");
  }

  return data as OpenSSHEd25519KeyPair;
}

OpenSSHRsaPublicKey parsePemRsaPublicKey(String keyText) {
  final der = _decodePemBlock(keyText, "RSA PUBLIC KEY");
  final reader = _DerReader(der);
  reader.readSequence();
  final modulus = reader.readInteger();
  final exponent = reader.readInteger();

  return OpenSSHRsaPublicKey(modulus: modulus, publicExponent: exponent);
}

OpenSSHRsaKeyPair parsePemRsaPrivateKey(String keyText) {
  final der = _decodePemBlock(keyText, "RSA PRIVATE KEY");
  final reader = _DerReader(der);
  reader.readSequence();
  reader.readInteger(); // version
  final modulus = reader.readInteger();
  final publicExponent = reader.readInteger();
  final privateExponent = reader.readInteger();
  final prime1 = reader.readInteger();
  final prime2 = reader.readInteger();
  reader.readInteger(); // exponent1
  reader.readInteger(); // exponent2
  final coefficient = reader.readInteger();

  return OpenSSHRsaKeyPair(
    modulus: modulus,
    publicExponent: publicExponent,
    privateExponent: privateExponent,
    prime1: prime1,
    prime2: prime2,
    iqmp: coefficient,
  );
}

Uint8List _extractOpenSSHPrivateBlock(String keyText) {
  final normalized = _normalizeOpenSSHKeyBlob(keyText);
  final raw = Uint8List.fromList(base64.decode(normalized));
  final reader = _OpenSSHReader(raw);

  final magicBytes = reader.readBytes(_opensshKeyMagic.length);
  final magic = utf8.decode(magicBytes);
  if (magic != _opensshKeyMagic) {
    throw FormatException("Unsupported OpenSSH key header: $magic");
  }

  if (reader.peekByte() == 0) {
    reader.readUint8(); // skip null terminator that follows the magic string
  }

  final cipherName = reader.readString();
  final kdfName = reader.readString();
  reader.readLengthPrefixedBytes(); // kdf options

  if (cipherName != "none" || kdfName != "none") {
    throw FormatException("Encrypted OpenSSH keys are not supported.");
  }

  final keyCount = reader.readUint32();
  if (keyCount < 1) {
    throw FormatException("OpenSSH key does not contain any entries.");
  }

  reader.readLengthPrefixedBytes(); // public key blob
  return reader.readLengthPrefixedBytes();
}

(String keyType, Object data) _parseOpenSSHPrivateKeyBlock(
  Uint8List privateBlock,
) {
  final reader = _OpenSSHReader(privateBlock);
  final firstCheck = reader.readUint32();
  final secondCheck = reader.readUint32();
  if (firstCheck != secondCheck) {
    throw FormatException("OpenSSH private key check integers do not match.");
  }

  final keyType = reader.readString();
  switch (keyType) {
    case rsaKeyType:
      return (keyType, _readOpenSSHRsaPrivateKey(reader));
    case ed25519KeyType:
      return (keyType, _readOpenSshEd25519PrivateKey(reader));
    default:
      throw FormatException("Unsupported OpenSSH key type: $keyType");
  }
}

OpenSSHRsaPublicKey _parseOpenSSHPublicKeyBlob(Uint8List blob) {
  final reader = _OpenSSHReader(blob);
  final keyType = reader.readString();
  if (keyType != rsaKeyType) {
    throw FormatException("Unsupported OpenSSH public key type: $keyType");
  }

  final publicExponent = reader.readMpInt();
  final modulus = reader.readMpInt();

  return OpenSSHRsaPublicKey(modulus: modulus, publicExponent: publicExponent);
}

OpenSSHRsaKeyPair _readOpenSSHRsaPrivateKey(_OpenSSHReader reader) {
  final modulus = reader.readMpInt();
  final publicExponent = reader.readMpInt();
  final privateExponent = reader.readMpInt();
  final iqmp = reader.readMpInt();
  final prime1 = reader.readMpInt();
  final prime2 = reader.readMpInt();
  reader.readString(); // comment

  return OpenSSHRsaKeyPair(
    modulus: modulus,
    publicExponent: publicExponent,
    privateExponent: privateExponent,
    iqmp: iqmp,
    prime1: prime1,
    prime2: prime2,
  );
}

Uint8List _decodePemBlock(String keyText, String label) {
  final begin = "-----BEGIN $label-----";
  final end = "-----END $label-----";
  final startIndex = keyText.indexOf(begin);
  if (startIndex < 0) {
    throw FormatException("PEM block for $label is missing the begin marker.");
  }

  final endIndex = keyText.indexOf(end, startIndex + begin.length);
  if (endIndex < 0) {
    throw FormatException("PEM block for $label is missing the end marker.");
  }

  final content = keyText.substring(startIndex + begin.length, endIndex);
  final normalized = content.replaceAll(RegExp(r'\s+'), '');
  if (normalized.isEmpty) {
    throw FormatException("$label PEM block is empty.");
  }

  return base64.decode(normalized);
}

bool _hasPemBlock(String keyText, String label) {
  return keyText.contains("-----BEGIN $label-----");
}

const _opensshKeyMagic = "openssh-key-v1";

_OpenSSHReader _readerFromBase64(String keyBase64) {
  final normalized = keyBase64.replaceAll(RegExp(r'\s+'), '');
  final raw = Uint8List.fromList(base64.decode(normalized));
  return _OpenSSHReader(raw);
}

String _normalizeOpenSSHKeyBlob(String keyText) {
  final lines = keyText.split(RegExp(r'\r?\n')).map((line) => line.trim());
  final filtered = lines.where(
    (line) => line.isNotEmpty && !line.startsWith("-----"),
  );
  final joined = filtered.join();
  if (joined.isEmpty) {
    throw FormatException("OpenSSH key text is empty.");
  }
  return joined.replaceAll(RegExp(r'\s+'), '');
}

class _DerReader {
  final Uint8List buffer;
  int _offset = 0;

  _DerReader(this.buffer);

  void readSequence() {
    _expectTag(0x30);
    _readLength();
  }

  Uint8List readInteger() {
    _expectTag(0x02);
    final length = _readLength();
    return readBytes(length);
  }

  Uint8List readBytes(int length) {
    _ensureAvailable(length);
    final start = _offset;
    _offset += length;
    return buffer.sublist(start, _offset);
  }

  int _readLength() {
    final first = _readByte();
    if (first & 0x80 == 0) {
      return first;
    }

    final lengthBytes = first & 0x7f;
    if (lengthBytes == 0) {
      throw FormatException("Indefinite DER lengths are not supported.");
    }

    var length = 0;
    for (var i = 0; i < lengthBytes; i++) {
      length = (length << 8) | _readByte();
    }

    return length;
  }

  int _readByte() {
    _ensureAvailable(1);
    return buffer[_offset++];
  }

  void _expectTag(int tag) {
    final actual = _readByte();
    if (actual != tag) {
      throw FormatException(
        "Unexpected DER tag: 0x${actual.toRadixString(16)}.",
      );
    }
  }

  void _ensureAvailable(int count) {
    if (_offset + count > buffer.length) {
      throw FormatException("Unexpected end of DER data.");
    }
  }
}

class _OpenSSHReader {
  final Uint8List buffer;
  final ByteData view;
  int _offset = 0;

  _OpenSSHReader(this.buffer)
    : view = ByteData.view(buffer.buffer, buffer.offsetInBytes, buffer.length);

  int readUint32() {
    _ensureAvailable(4);
    final value = view.getUint32(_offset);
    _offset += 4;
    return value;
  }

  Uint8List readLengthPrefixedBytes() {
    final length = readUint32();
    return readBytes(length);
  }

  Uint8List readBytes(int length) {
    _ensureAvailable(length);
    final start = _offset;
    final end = _offset + length;
    _offset = end;
    return buffer.sublist(start, end);
  }

  String readString() => utf8.decode(readLengthPrefixedBytes());

  Uint8List readMpInt() => readLengthPrefixedBytes();

  int readUint8() {
    _ensureAvailable(1);
    return buffer[_offset++];
  }

  int peekByte() {
    _ensureAvailable(1);
    return buffer[_offset];
  }

  void _ensureAvailable(int count) {
    if (_offset + count > buffer.length) {
      throw FormatException("Unexpected end of OpenSSH binary data.");
    }
  }
}
