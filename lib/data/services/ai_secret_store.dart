import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AiSecretStore {
  AiSecretStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<void> write(String id, String value) =>
      _storage.write(key: 'tomoread.ai.$id', value: value);

  Future<String?> read(String id) => _storage.read(key: 'tomoread.ai.$id');

  Future<void> delete(String id) => _storage.delete(key: 'tomoread.ai.$id');
}
