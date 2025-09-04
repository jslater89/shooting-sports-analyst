import 'dart:convert';
import 'dart:io';

import 'package:encrypt/encrypt.dart';
import 'package:shooting_sports_analyst/config/secure_config.dart';

class EncryptedFileStore extends SecureStorageProvider {
  EncryptedFileStore({this.path = "db/efs.db", required this.key}) {
    aes = AES(Key.fromUtf8(key));
  }

  final String path;
  final String key;
  late final AES aes;

  File getFile() {
    var f = File(path);
    if(!f.existsSync()) {
      f.createSync(recursive: true);
    }
    return f;
  }

  File getIvFile() {
    var f = File("$path.iv");
    if(!f.existsSync()) {
      f.createSync(recursive: true);
    }
    return f;
  }

  Future<Map<String, String>> getEntries() async {
    var f = getFile();
    var ivFile = getIvFile();
    var ivContents = await ivFile.readAsString();
    var iv = IV.fromBase64(ivContents);
    var contents = await f.readAsString();
    var decrypter = Encrypter(aes);
    var decrypted = decrypter.decrypt(Encrypted.fromBase64(contents), iv: iv);

    return jsonDecode(decrypted);
  }

  Future<File> saveEntries(Map<String, String> entries) async {
    var f = getFile();
    var ivFile = getIvFile();
    var iv = IV.fromLength(16);
    var encrypter = Encrypter(aes);
    var encrypted = encrypter.encrypt(jsonEncode(entries), iv: iv);
    await ivFile.writeAsString(iv.base64);
    return f.writeAsString(encrypted.base64);
  }

  @override
  Future<void> delete(String key) async {
    var entries = await getEntries();
    entries.remove(key);
    await saveEntries(entries);
  }

  @override
  Future<String?> read(String key) async {
    var entries = await getEntries();
    return entries[key];
  }

  @override
  Future<void> write(String key, String value) async {
    var entries = await getEntries();
    entries[key] = value;
    await saveEntries(entries);
  }
}
