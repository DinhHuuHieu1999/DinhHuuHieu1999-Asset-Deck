import 'asset_check.dart';
import 'asset_read.dart';
import 'asset_serial_check.dart';
import 'asset_selection_export.dart';
import 'asset_sort.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'asset.dart';
import 'asset_location.dart';
import 'asset_location_overview.dart';
import 'asset_dates.dart';
import 'asset_warranty.dart';
import 'asset_warranty_overview.dart';
import 'asset_overview.dart';
import 'asset_export.dart';
import 'asset_export_v2.dart';
import 'asset_export_v3.dart';
import 'asset_import.dart';
import 'asset_import_v2.dart';
import 'asset_import_v3.dart';
import 'asset_session.dart';
import 'asset_store.dart';

/// Native JSON client with bounded responses and in-memory credentials only.
/// Adapted from ToolDeck's selected auth/CSRF/session transport; no other domains.
class AssetApi
    implements
        AssetSession,
        AssetReadSource,
        AssetCheckSource,
        AssetCheckBeforeSource,
        AssetSerialCheckSource,
        AssetExportSource,
        AssetExportV2Source,
        AssetExportV3Source,
        AssetSelectionExportSource,
        AssetImportSource,
        AssetImportV2Source,
        AssetImportV3Source,
        AssetOverviewSource,
        AssetDatesSource,
        AssetLocationSource,
        AssetLocationOverviewSource,
        AssetWarrantySource,
        AssetWarrantyOverviewSource {
  AssetApi(
    Uri endpoint, {
    bool allowLocalHttp = false,
    this.timeout = const Duration(seconds: 15),
  }) : baseUrl = _endpoint(endpoint, allowLocalHttp) {
    if (timeout <= Duration.zero)
      throw ArgumentError('Timeout must be positive');
  }
  final Uri baseUrl;
  final Duration timeout;
  String? _token, _csrfToken;
  List<Cookie> _cookies = [];
  Future<void>? _csrfFuture;
  final _changes = StreamController<int>.broadcast();
  final _active = <HttpClient>{};
  int _epoch = 0;
  bool _closed = false;
  AssetAccount? _account;
  @override
  AssetAccount? get account => _account;
  @override
  int get sessionRevision => _epoch;
  @override
  Stream<int> get sessionChanges => _changes.stream;

  static Uri _endpoint(Uri value, bool allowLocalHttp) {
    final local = [
      'localhost',
      '127.0.0.1',
      '::1',
      '[::1]',
    ].contains(value.host);
    if ((value.scheme != 'https' &&
            !(allowLocalHttp && local && value.scheme == 'http')) ||
        value.host.isEmpty ||
        value.userInfo.isNotEmpty ||
        value.hasQuery ||
        value.hasFragment ||
        value.path.replaceAll(RegExp(r'/+$'), '') != '/api/v1') {
      throw ArgumentError('Use an HTTPS endpoint ending in /api/v1');
    }
    return value.replace(path: '/api/v1/');
  }

  void _current(int epoch) {
    if (_closed) throw const AssetFailure('Client is closed');
    if (epoch != _epoch)
      throw const AssetFailure('Session changed; sign in again');
  }

  int _requireAccount() {
    _current(_epoch);
    if (_account == null)
      throw const AssetFailure('Please sign in again', statusCode: 401);
    return _epoch;
  }

  int _beginAuth() {
    _current(_epoch);
    final hadAccount = _account != null;
    _clear();
    if (hadAccount) _changes.add(_epoch);
    return _epoch;
  }

  void _accept(Map<String, Object?> result, int epoch) {
    _current(epoch);
    final token = result['accessToken'];
    final user = result['user'];
    if (token is! String ||
        token.isEmpty ||
        token.length > 16384 ||
        RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(token) ||
        user is! Map<String, Object?> ||
        user['id'] is! String ||
        !RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(user['id']! as String) ||
        user['name'] is! String ||
        (user['name']! as String).isEmpty ||
        (user['name']! as String).length > 100) {
      throw const AssetFailure('Invalid sign-in response');
    }
    _token = token;
    _account = AssetAccount(
      id: (user['id']! as String).toLowerCase(),
      name: user['name']! as String,
    );
    _changes.add(epoch);
  }

  @override
  Future<void> login(String identifier, String password) async {
    if (identifier.trim().length < 3 ||
        identifier.trim().length > 100 ||
        password.length < 8 ||
        password.length > 72) {
      throw const AssetFailure(
        'Enter a valid identifier and password (8-72 characters).',
        definitelyNotSent: true,
      );
    }
    final epoch = _beginAuth();
    _accept(
      await _request('POST', 'auth/login', epoch, {
        'identifier': identifier.trim(),
        'password': password,
      }),
      epoch,
    );
  }

  @override
  Future<void> register({
    required String email,
    required String username,
    required String name,
    required String password,
  }) async {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim()) ||
        !RegExp(r'^[a-zA-Z0-9._]{3,30}$').hasMatch(username.trim()) ||
        name.trim().isEmpty ||
        name.trim().length > 100 ||
        password.length < 8 ||
        password.length > 72) {
      throw const AssetFailure(
        'Check email, username (3-30), name (1-100) and password (8-72).',
        definitelyNotSent: true,
      );
    }
    final epoch = _beginAuth();
    _accept(
      await _request('POST', 'auth/register', epoch, {
        'email': email.trim(),
        'username': username.trim(),
        'name': name.trim(),
        'password': password,
      }),
      epoch,
    );
  }

  @override
  Future<AssetPage> list({
    String sort = 'updated_desc',
    bool unchecked = false,
    String checkBefore = '',
    required String query,
    required String status,
    String category = '',
    required int offset,
  }) async {
    assetCheckQuery(unchecked: unchecked, before: checkBefore);
    final epoch = _requireAccount();
    if (!assetSorts.contains(sort)) {
      throw const AssetFailure(
        'Invalid inventory sort',
        definitelyNotSent: true,
      );
    }
    if (category.runes.length > 64 ||
        category.contains('\u0000') ||
        query.length > 120 ||
        query.contains('\u0000') ||
        (status.isNotEmpty && !assetStatuses.contains(status)) ||
        offset < 0 ||
        offset > 100000) {
      throw const AssetFailure('Invalid inventory filters');
    }
    final path = Uri(
      path: 'assets',
      queryParameters: {
        ...assetCheckQuery(unchecked: unchecked, before: checkBefore),
        'q': query.trim(),
        'status': status,
        if (category.trim().isNotEmpty) 'category': category.trim(),
        'offset': '$offset',
        if (sort != 'updated_desc') 'sort': sort,
      },
    ).toString();
    final result = await _request('GET', path, epoch);
    _current(epoch);
    try {
      return AssetPage.fromJson(result, offset: offset);
    } on FormatException {
      throw const AssetFailure('Invalid inventory response');
    }
  }

  /// Fetch complete owner counts independently of every inventory list filter.
  @override
  Future<AssetWarrantyOverview> warrantyOverview({String asOf = ''}) async {
    final epoch = _requireAccount();
    if (asOf.isNotEmpty && !isAssetCalendarDate(asOf)) {
      throw const AssetFailure(
        'Invalid warranty reference date',
        definitelyNotSent: true,
      );
    }
    final path = Uri(
      path: 'assets/warranty/overview',
      queryParameters: asOf.isEmpty ? null : {'asOf': asOf},
    ).toString();
    final result = await _request('GET', path, epoch);
    _current(epoch);
    try {
      return AssetWarrantyOverview.fromJson(result, asOf: asOf);
    } on FormatException {
      throw const AssetFailure('Invalid warranty overview response');
    }
  }

  /// Read a separate warranty page; subsequent pages preserve the UTC reference.
  @override
  Future<AssetWarrantyPage> listWarranty({
    String sort = 'updated_desc',
    bool unchecked = false,
    String checkBefore = '',
    required String query,
    required String status,
    String category = '',
    required String warranty,
    String asOf = '',
    required int offset,
  }) async {
    assetCheckQuery(unchecked: unchecked, before: checkBefore);
    final epoch = _requireAccount();
    if (!assetSorts.contains(sort)) {
      throw const AssetFailure(
        'Invalid inventory sort',
        definitelyNotSent: true,
      );
    }
    if (!assetWarrantyFilters.contains(warranty) ||
        (asOf.isNotEmpty && !isAssetCalendarDate(asOf)) ||
        (offset > 0 && asOf.isEmpty) ||
        offset < 0 ||
        offset > 100000 ||
        query.length > 120 ||
        query.contains('\u0000') ||
        category.runes.length > 64 ||
        category.contains('\u0000') ||
        (status.isNotEmpty && !assetStatuses.contains(status))) {
      throw const AssetFailure(
        'Invalid warranty filters',
        definitelyNotSent: true,
      );
    }
    final path = Uri(
      path: 'assets/warranty',
      queryParameters: {
        ...assetCheckQuery(unchecked: unchecked, before: checkBefore),
        'q': query.trim(),
        'status': status,
        if (category.trim().isNotEmpty) 'category': category.trim(),
        'warranty': warranty,
        if (asOf.isNotEmpty) 'asOf': asOf,
        'offset': '$offset',
        if (sort != 'updated_desc') 'sort': sort,
      },
    ).toString();
    final result = await _request('GET', path, epoch);
    _current(epoch);
    try {
      return AssetWarrantyPage.fromJson(
        result,
        warranty: warranty,
        asOf: asOf,
        offset: offset,
      );
    } on FormatException {
      throw const AssetFailure('Invalid warranty inventory response');
    }
  }

  /// Read manual location with the current authenticated session.
  @override
  Future<AssetLocation> readLocation(String id) async {
    final epoch = _requireAccount();
    _locationIdentity(id);
    final value = await _request('GET', 'assets/$id/location', epoch);
    _current(epoch);
    return _location(value, id);
  }

  /// Replace location once; an unknown write outcome never triggers a retry.
  @override
  Future<AssetLocation> updateLocation(
    AssetLocation original,
    String? location,
  ) async {
    final epoch = _requireAccount();
    final Map<String, Object?> body;
    try {
      body = original.replacement(location);
    } on FormatException {
      throw const AssetFailure(
        'Invalid asset location or version',
        definitelyNotSent: true,
      );
    }
    final value = await _request(
      'PUT',
      'assets/${original.id}/location',
      epoch,
      body,
    );
    _current(epoch);
    final result = _location(value, original.id);
    if (result.version != original.version + 1 ||
        result.location != body['location']) {
      throw const AssetFailure(
        'Invalid location update response; reload before another write',
      );
    }
    return result;
  }

  void _locationIdentity(String id) {
    try {
      AssetLocation.fromJson({'id': id, 'version': 1, 'location': null});
    } on FormatException {
      throw const AssetFailure(
        'Invalid asset identity',
        definitelyNotSent: true,
      );
    }
  }

  AssetLocation _location(Map<String, Object?> value, String id) {
    try {
      final result = AssetLocation.fromJson(value);
      if (result.id.toLowerCase() != id.toLowerCase())
        throw const FormatException();
      return result;
    } on FormatException {
      throw const AssetFailure(
        'Invalid asset location response; reload before another write',
      );
    }
  }

  /// Fetch a complete owner snapshot; reject malformed or late-session results.
  @override
  Future<AssetLocationOverview> locationOverview() async {
    final epoch = _requireAccount();
    final result = await _request('GET', 'assets/locations/overview', epoch);
    _current(epoch);
    try {
      return AssetLocationOverview.fromJson(result);
    } on FormatException {
      throw const AssetFailure('Invalid location overview response');
    }
  }

  /// Fetch explicit location filters before paging, separate from the legacy list.
  @override
  Future<AssetLocationPage> listLocations({
    String sort = 'updated_desc',
    bool unchecked = false,
    String checkBefore = '',
    required String query,
    required String status,
    String category = '',
    required int offset,
    String locationMode = 'all',
    String? location,
    String warranty = '',
    String asOf = '',
  }) async {
    assetCheckQuery(unchecked: unchecked, before: checkBefore);
    final epoch = _requireAccount();
    if (!assetSorts.contains(sort)) {
      throw const AssetFailure(
        'Invalid inventory sort',
        definitelyNotSent: true,
      );
    }
    String? label;
    try {
      if ((warranty.isNotEmpty && !assetWarrantyFilters.contains(warranty)) ||
          (asOf.isNotEmpty &&
              (!isAssetCalendarDate(asOf) || warranty.isEmpty)) ||
          (warranty.isNotEmpty && offset > 0 && asOf.isEmpty) ||
          !['all', 'unknown', 'exact'].contains(locationMode) ||
          (locationMode != 'exact' && location != null) ||
          (locationMode == 'exact' && location == null) ||
          query.length > 120 ||
          query.contains('\u0000') ||
          category.runes.length > 64 ||
          category.contains('\u0000') ||
          (status.isNotEmpty && !assetStatuses.contains(status)) ||
          offset < 0 ||
          offset > 100000)
        throw const FormatException();
      label = normalizeAssetLocation(location);
    } on FormatException {
      throw const AssetFailure(
        'Invalid inventory location filters',
        definitelyNotSent: true,
      );
    }
    final path = Uri(
      path: 'assets/locations/inventory',
      queryParameters: {
        ...assetCheckQuery(unchecked: unchecked, before: checkBefore),
        'q': query.trim(),
        'status': status,
        'category': category.trim(),
        'offset': '$offset',
        if (sort != 'updated_desc') 'sort': sort,
        'locationMode': locationMode,
        if (warranty.isNotEmpty) 'warranty': warranty,
        if (asOf.isNotEmpty) 'asOf': asOf,
        if (label != null) 'location': label,
      },
    ).toString();
    final value = await _request('GET', path, epoch);
    _current(epoch);
    try {
      return AssetLocationPage.fromJson(
        value,
        offset: offset,
        warranty: warranty,
        asOf: asOf,
      );
    } on FormatException {
      throw const AssetFailure('Invalid inventory location response');
    }
  }

  /// Reuse validated transports with an explicit server-side NULL filter.
  @override
  Future<AssetCheckPage> listUnchecked({
    required String query,
    required String status,
    required int offset,
    String sort = 'updated_desc',
    String category = '',
    bool includeLocation = false,
    String locationMode = 'all',
    String? location,
    String warranty = '',
    String asOf = '',
  }) async {
    if (includeLocation) {
      final result = await listLocations(
        unchecked: true,
        query: query,
        status: status,
        offset: offset,
        sort: sort,
        category: category,
        locationMode: locationMode,
        location: location,
        warranty: warranty,
        asOf: asOf,
      );
      return AssetCheckPage(
        AssetPage(
          result.items.map((item) => item.asset).toList(),
          result.nextOffset,
        ),
        locations: {
          for (final item in result.items) item.asset.id: item.location,
        },
        warranty: result.warrantyPage,
      );
    }
    if (locationMode != 'all' || location != null) {
      throw const AssetFailure(
        'Location filtering is unavailable',
        definitelyNotSent: true,
      );
    }
    if (warranty.isNotEmpty) {
      final result = await listWarranty(
        unchecked: true,
        query: query,
        status: status,
        offset: offset,
        sort: sort,
        category: category,
        warranty: warranty,
        asOf: asOf,
      );
      return AssetCheckPage(
        AssetPage(
          result.items.map((item) => item.asset).toList(),
          result.nextOffset,
        ),
        warranty: result,
      );
    }
    if (asOf.isNotEmpty)
      throw const AssetFailure(
        'Reference date requires warranty filter',
        definitelyNotSent: true,
      );
    return AssetCheckPage(
      await list(
        unchecked: true,
        query: query,
        status: status,
        offset: offset,
        sort: sort,
        category: category,
      ),
    );
  }

  /// List dated assets strictly before an explicit cutoff without changing legacy stores.
  @override
  Future<AssetCheckPage> listCheckedBefore({
    required String checkBefore,
    required String query,
    required String status,
    required int offset,
    String sort = 'updated_desc',
    String category = '',
    bool includeLocation = false,
    String locationMode = 'all',
    String? location,
    String warranty = '',
    String asOf = '',
  }) async {
    if (checkBefore.isEmpty)
      throw const AssetFailure(
        'Check cutoff is required',
        definitelyNotSent: true,
      );
    if (includeLocation) {
      final result = await listLocations(
        checkBefore: checkBefore,
        query: query,
        status: status,
        offset: offset,
        sort: sort,
        category: category,
        locationMode: locationMode,
        location: location,
        warranty: warranty,
        asOf: asOf,
      );
      return AssetCheckPage(
        AssetPage(
          result.items.map((item) => item.asset).toList(),
          result.nextOffset,
        ),
        locations: {
          for (final item in result.items) item.asset.id: item.location,
        },
        warranty: result.warrantyPage,
      );
    }
    if (locationMode != 'all' || location != null) {
      throw const AssetFailure(
        'Location filtering is unavailable',
        definitelyNotSent: true,
      );
    }
    if (warranty.isNotEmpty) {
      final result = await listWarranty(
        checkBefore: checkBefore,
        query: query,
        status: status,
        offset: offset,
        sort: sort,
        category: category,
        warranty: warranty,
        asOf: asOf,
      );
      return AssetCheckPage(
        AssetPage(
          result.items.map((item) => item.asset).toList(),
          result.nextOffset,
        ),
        warranty: result,
      );
    }
    if (asOf.isNotEmpty)
      throw const AssetFailure(
        'Reference date requires warranty filter',
        definitelyNotSent: true,
      );
    return AssetCheckPage(
      await list(
        checkBefore: checkBefore,
        query: query,
        status: status,
        offset: offset,
        sort: sort,
        category: category,
      ),
    );
  }

  /// Read the separate manual-check snapshot under the current session.
  @override
  Future<AssetCheck> readCheckDate(String id) async {
    final epoch = _requireAccount();
    _dateIdentity(id);
    final value = await _request('GET', 'assets/$id/check-date', epoch);
    _current(epoch);
    return _checkDate(value, id);
  }

  /// Submit once; uncertain writes require reload rather than automatic retry.
  @override
  Future<AssetCheck> updateCheckDate(AssetCheck original, String? date) async {
    final epoch = _requireAccount();
    _dateIdentity(original.id);
    final Map<String, Object?> body;
    try {
      body = original.replacement(date);
    } on FormatException {
      throw const AssetFailure(
        'Invalid check date or version',
        definitelyNotSent: true,
      );
    }
    final value = await _request(
      'PUT',
      'assets/${original.id}/check-date',
      epoch,
      body,
    );
    _current(epoch);
    final result = _checkDate(value, original.id);
    if (result.version != original.version + 1 ||
        result.lastCheckedOn != date) {
      throw const AssetFailure(
        'Invalid check date update response; reload before another write',
      );
    }
    return result;
  }

  AssetCheck _checkDate(Map<String, Object?> value, String id) {
    try {
      final result = AssetCheck.fromJson(value);
      if (result.id.toLowerCase() != id.toLowerCase())
        throw const FormatException('Unexpected asset identity');
      return result;
    } on FormatException {
      throw const AssetFailure(
        'Invalid asset check date response; reload before another write',
      );
    }
  }

  /// Read dates separately without changing the legacy inventory contract.
  @override
  Future<AssetDates> readDates(String id) async {
    final epoch = _requireAccount();
    _dateIdentity(id);
    final value = await _request('GET', 'assets/$id/dates', epoch);
    _current(epoch);
    return _dates(value, id);
  }

  /// Submit one explicit shared-version update; transport never retries writes.
  @override
  Future<AssetDates> updateDates(
    AssetDates original,
    AssetDatesInput input,
  ) async {
    final epoch = _requireAccount();
    _dateIdentity(original.id);
    final Map<String, Object?> body;
    try {
      body = input.toJson(version: original.version);
    } on FormatException {
      throw const AssetFailure(
        'Invalid purchase/warranty dates or version',
        definitelyNotSent: true,
      );
    }
    final value = await _request(
      'PUT',
      'assets/${original.id}/dates',
      epoch,
      body,
    );
    _current(epoch);
    final result = _dates(value, original.id);
    if (result.version != original.version + 1 ||
        result.input.purchasedOn != input.purchasedOn ||
        result.input.warrantyExpiresOn != input.warrantyExpiresOn) {
      throw const AssetFailure(
        'Invalid dates update response; reload before another write',
      );
    }
    return result;
  }

  void _dateIdentity(String id) {
    if (!RegExp(
      r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
    ).hasMatch(id)) {
      throw const AssetFailure(
        'Reload this asset before editing dates',
        definitelyNotSent: true,
      );
    }
  }

  AssetDates _dates(Map<String, Object?> value, String id) {
    try {
      final result = AssetDates.fromJson(value);
      if (result.id.toLowerCase() != id.toLowerCase()) {
        throw const FormatException('Unexpected asset identity');
      }
      return result;
    } on FormatException {
      throw const AssetFailure(
        'Invalid asset dates response; reload before another write',
      );
    }
  }

  /// Check exact serials across the owner inventory, rejecting stale session results.
  /// Read one validated ID; reject stale-session and wrong-identity responses.
  @override
  Future<AssetRecord> readAsset(String id) async {
    final epoch = _requireAccount();
    if (!RegExp(
      r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
    ).hasMatch(id)) {
      throw const AssetFailure('Invalid asset ID', definitelyNotSent: true);
    }
    final value = await _request('GET', 'assets/$id', epoch);
    _current(epoch);
    final result = _record(value);
    if (result.id.toLowerCase() != id.toLowerCase()) {
      throw const AssetFailure('Asset response identity mismatch');
    }
    return result;
  }

  @override
  Future<bool> serialDuplicate(String serial, {String? excludeId}) async {
    final epoch = _requireAccount();
    final normalized = serial.trim();
    if (normalized.runes.length > 120 ||
        normalized.contains('\u0000') ||
        (excludeId != null &&
            !RegExp(
              r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
            ).hasMatch(excludeId))) {
      throw const AssetFailure(
        'Invalid serial check input',
        definitelyNotSent: true,
      );
    }
    final path = Uri(
      path: 'assets/serial-duplicates',
      queryParameters: {
        'serial': normalized,
        if (excludeId != null) 'excludeId': excludeId,
      },
    ).toString();
    final result = await _request('GET', path, epoch);
    _current(epoch);
    try {
      return parseAssetSerialCheck(result);
    } on FormatException {
      throw const AssetFailure('Invalid serial check response');
    }
  }

  /// Fetch complete counts without passing list filters or accepting stale sessions.
  @override
  Future<AssetOverview> overview() async {
    final epoch = _requireAccount();
    final result = await _request('GET', 'assets/overview', epoch);
    _current(epoch);
    try {
      return AssetOverview.fromJson(result);
    } on FormatException {
      throw const AssetFailure('Invalid inventory overview response');
    }
  }

  /// Fetch one complete snapshot and reject results from an invalidated session.
  @override
  Future<AssetExport> exportInventory({
    required AssetExportDigest digest,
  }) async {
    final epoch = _requireAccount();
    final value = await _request('GET', 'assets/export', epoch);
    _current(epoch);
    try {
      final result = await AssetExport.parse(value, digest: digest);
      _current(epoch);
      return result;
    } on FormatException {
      throw const AssetFailure('Invalid inventory export or checksum');
    }
  }

  /// Fetch a date-aware snapshot without accepting a stale account's result.
  @override
  Future<AssetExportV2> exportInventoryV2({
    required AssetExportDigest digest,
  }) async {
    final epoch = _requireAccount();
    final value = await _request('GET', 'assets/export/v2', epoch);
    _current(epoch);
    try {
      final result = await AssetExportV2.parse(value, digest: digest);
      _current(epoch);
      return result;
    } on FormatException {
      throw const AssetFailure('Invalid inventory v2 export or checksum');
    }
  }

  /// Fetch a location-aware snapshot without accepting a stale account's result.
  @override
  Future<AssetExportV3> exportInventoryV3({
    required AssetExportDigest digest,
  }) async {
    final epoch = _requireAccount();
    final value = await _request('GET', 'assets/export/v3', epoch);
    _current(epoch);
    try {
      final result = await AssetExportV3.parse(value, digest: digest);
      _current(epoch);
      return result;
    } on FormatException {
      throw const AssetFailure('Invalid inventory v3 export or checksum');
    }
  }

  /// Verify selection identity and session after transport and asynchronous digest.
  @override
  Future<AssetSelectionExport> exportSelection({
    required AssetSelectionScope scope,
    required AssetExportDigest digest,
  }) async {
    final epoch = _requireAccount();
    final expected = scope.toQuery();
    final path = Uri(
      path: 'assets/export/selection',
      queryParameters: expected,
    ).toString();
    final value = await _request('GET', path, epoch);
    _current(epoch);
    try {
      final result = await AssetSelectionExport.parse(value, digest: digest);
      _current(epoch);
      final actual = result.scope.toQuery();
      if (actual.length != expected.length ||
          expected.entries.any((entry) => actual[entry.key] != entry.value)) {
        throw const FormatException('Selection response scope mismatch');
      }
      return result;
    } on FormatException {
      throw const AssetFailure('Invalid selection export, scope or checksum');
    }
  }

  @override
  Future<AssetRecord> create(AssetInput input) async {
    final epoch = _requireAccount();
    return _record(await _request('POST', 'assets', epoch, input.toJson()));
  }

  @override
  Future<AssetRecord> update(AssetRecord original, AssetInput input) async {
    final epoch = _requireAccount();
    // Validate server identity before it can become a path segment.
    if (!RegExp(
          r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
        ).hasMatch(original.id) ||
        original.version < 1 ||
        original.version > 2147483646) {
      throw const AssetFailure('Reload this asset before editing');
    }
    final result = _record(
      await _request('PUT', 'assets/${original.id}', epoch, {
        ...input.toJson(),
        'version': original.version,
      }),
    );
    if (result.id.toLowerCase() != original.id.toLowerCase() ||
        result.version != original.version + 1) {
      throw const AssetFailure(
        'Invalid update response; refresh before another write',
      );
    }
    return result;
  }

  AssetRecord _record(Map<String, Object?> value) {
    try {
      return AssetRecord.fromJson(value);
    } on FormatException {
      throw const AssetFailure(
        'Invalid asset response; refresh before another write',
      );
    }
  }

  /// Submit exactly one account/session-bound operation; never retries internally.
  @override
  Future<AssetImportReceipt> importInventory(
    AssetImportDraft draft, {
    required int sessionRevision,
  }) async {
    final epoch = _requireAccount();
    if (epoch != sessionRevision || _account!.id != draft.accountId) {
      throw const AssetFailure(
        'Import session changed; review the target account again',
        definitelyNotSent: true,
      );
    }
    final response = await _request(
      'POST',
      'assets/import',
      epoch,
      jsonDecode(draft.json) as Map<String, Object?>,
    );
    _current(epoch);
    try {
      return AssetImportReceipt.parse(response, draft);
    } on FormatException {
      throw const AssetFailure(
        'Import receipt unavailable; retain the same request key',
      );
    }
  }

  /// Submit exactly one account/session-bound operation; never retries internally.
  @override
  Future<AssetImportV2Receipt> importInventoryV2(
    AssetImportV2Draft draft, {
    required int sessionRevision,
  }) async {
    final epoch = _requireAccount();
    if (epoch != sessionRevision || _account!.id != draft.accountId) {
      throw const AssetFailure(
        'Import session changed; review the target account again',
        definitelyNotSent: true,
      );
    }
    await _csrf(epoch);
    _current(epoch);
    final response = await _send(
      'POST',
      'assets/import/v2',
      epoch,
      null,
      draft.json,
    );
    _current(epoch);
    try {
      return AssetImportV2Receipt.parse(response, draft);
    } on FormatException {
      throw const AssetFailure(
        'Import receipt unavailable; retain the same request key',
      );
    }
  }

  /// Submit exactly one account/session-bound operation; never retries internally.
  @override
  Future<AssetImportV3Receipt> importInventoryV3(
    AssetImportV3Draft draft, {
    required int sessionRevision,
  }) async {
    final epoch = _requireAccount();
    if (epoch != sessionRevision || _account!.id != draft.accountId) {
      throw const AssetFailure(
        'Import session changed; review the target account again',
        definitelyNotSent: true,
      );
    }
    await _csrf(epoch);
    _current(epoch);
    final response = await _send(
      'POST',
      'assets/import/v3',
      epoch,
      null,
      draft.json,
    );
    _current(epoch);
    try {
      return AssetImportV3Receipt.parse(response, draft);
    } on FormatException {
      throw const AssetFailure(
        'Import receipt unavailable; retain the same request key',
      );
    }
  }

  Future<void> _csrf(int epoch) async {
    _current(epoch);
    if (_csrfToken != null) return;
    final future = _csrfFuture ??= _loadCsrf(epoch);
    try {
      await future;
    } catch (_) {
      if (identical(_csrfFuture, future)) _csrfFuture = null;
      rethrow;
    }
    _current(epoch);
  }

  Future<void> _loadCsrf(int epoch) async {
    final response = await _send('GET', 'csrf-token', epoch);
    _current(epoch);
    final token = response['token'];
    if (token is! String ||
        token.isEmpty ||
        token.length > 8192 ||
        RegExp(r'[\r\n\x00]').hasMatch(token) ||
        _cookies.isEmpty) {
      throw const AssetFailure('Invalid CSRF response');
    }
    _csrfToken = token;
  }

  Future<Map<String, Object?>> _request(
    String method,
    String path,
    int epoch, [
    Map<String, Object?>? body,
  ]) async {
    _current(epoch);
    if (method != 'GET') await _csrf(epoch);
    _current(epoch);
    return _send(method, path, epoch, body);
  }

  Future<Map<String, Object?>> _send(
    String method,
    String path,
    int epoch, [
    Map<String, Object?>? body,
    String? exactJson,
  ]) async {
    _current(epoch);
    final client = HttpClient()..connectionTimeout = timeout;
    _active.add(client);
    try {
      return await (() async {
        final request = await client.openUrl(method, baseUrl.resolve(path));
        _current(epoch);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(
          'x-request-timestamp',
          '${DateTime.now().millisecondsSinceEpoch}',
        );
        if (_token != null)
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer $_token',
          );
        if (method != 'GET') request.headers.set('x-csrf-token', _csrfToken!);
        request.cookies.addAll(
          _cookies.where(
            (cookie) =>
                (!cookie.secure || baseUrl.scheme == 'https') &&
                (cookie.expires == null ||
                    cookie.expires!.isAfter(DateTime.now())),
          ),
        );
        if (body != null || exactJson != null) {
          request.headers.contentType = ContentType.json;
          request.write(exactJson ?? jsonEncode(body));
        }
        final response = await request.close();
        _current(epoch);
        if (response.statusCode == 401) {
          signOut();
          throw const AssetFailure('Please sign in again', statusCode: 401);
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final message = switch (response.statusCode) {
            403 => 'Request rejected. Sign in again before another write.',
            409 => 'Asset changed or is unavailable; refresh before editing.',
            422 =>
              path == 'assets/export'
                  ? 'Inventory exceeds export limits (500 assets / 1 MiB); no partial export was produced.'
                  : path.split('?').first == 'assets/warranty/overview'
                  ? 'Warranty counts exceed the safe integer limit; no partial overview was returned.'
                  : path == 'assets/overview'
                  ? 'Inventory exceeds the overview limit (200 categories); no partial counts were returned.'
                  : 'Pagination limit reached; the list is incomplete. Narrow your filters.',
            429 => 'Too many requests. Wait before trying again.',
            _ => 'Request failed',
          };
          throw AssetFailure(message, statusCode: response.statusCode);
        }
        if (response.headers.contentType?.mimeType != 'application/json') {
          throw const AssetFailure('Invalid server response');
        }
        const limit = 1024 * 1024;
        if (response.contentLength > limit)
          throw const AssetFailure('Response is too large');
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          _current(epoch);
          if (bytes.length + chunk.length > limit)
            throw const AssetFailure('Response is too large');
          bytes.add(chunk);
        }
        _current(epoch);
        final decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
        if (decoded is! Map<String, Object?>)
          throw const AssetFailure('Invalid server response');
        if (path == 'csrf-token') {
          _cookies = response.cookies
              .where(
                (cookie) =>
                    cookie.name.isNotEmpty &&
                    (!cookie.secure || baseUrl.scheme == 'https') &&
                    (cookie.expires == null ||
                        cookie.expires!.isAfter(DateTime.now())),
              )
              .toList(growable: false);
        }
        return decoded;
      })().timeout(timeout);
    } on AssetFailure {
      rethrow;
    } on TimeoutException {
      throw const AssetFailure('Request timed out');
    } on FormatException {
      throw const AssetFailure('Invalid server response');
    } on IOException {
      throw const AssetFailure('Unable to connect securely to the server');
    } finally {
      client.close(force: true);
      _active.remove(client);
    }
  }

  void _clear() {
    _epoch++;
    _account = null;
    _token = null;
    _csrfToken = null;
    _csrfFuture = null;
    _cookies = [];
    for (final client in _active.toList()) {
      client.close(force: true);
    }
  }

  /// Discard credentials and pending requests, without revoking the server JWT.
  @override
  void signOut() {
    if (_closed) return;
    _clear();
    _changes.add(_epoch);
  }

  /// End all connections and discard the in-memory session.
  @override
  void close() {
    if (_closed) return;
    _clear();
    _closed = true;
    unawaited(_changes.close());
  }
}
