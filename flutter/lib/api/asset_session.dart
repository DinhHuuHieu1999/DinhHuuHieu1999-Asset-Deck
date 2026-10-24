import 'asset_store.dart';

/// Public account identity only; bearer tokens remain inside the client.
class AssetAccount {
  const AssetAccount({required this.id, required this.name});
  final String id, name;
}

/// Account lifecycle owned by the root app, including invalidation of private UI.
abstract interface class AssetSession implements AssetStore {
  AssetAccount? get account;
  int get sessionRevision;
  Stream<int> get sessionChanges;
  Future<void> login(String identifier, String password);
  Future<void> register({
    required String email,
    required String username,
    required String name,
    required String password,
  });
  void signOut();
  void close();
}
