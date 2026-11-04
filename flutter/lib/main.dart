import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api/asset_api.dart';
import 'asset_desk_app.dart';

/// Launch only with an explicit app-owned endpoint; never disable TLS validation.
void main() {
  const endpoint = String.fromEnvironment('ASSET_DESK_API_URL');
  if (endpoint.isEmpty) {
    runApp(
      const _ConfigurationMessage(
        'Set ASSET_DESK_API_URL to the HTTPS endpoint including /api/v1.',
      ),
    );
    return;
  }
  try {
    final api = AssetApi(
      Uri.parse(endpoint),
      allowLocalHttp:
          kDebugMode &&
          const bool.fromEnvironment('ASSET_DESK_ALLOW_LOCAL_HTTP'),
    );
    runApp(
      AssetDeskApp(
        session: api,
        enableSelectionExport: const bool.fromEnvironment(
          'ASSET_DESK_ENABLE_SELECTION_EXPORT',
        ),
        enableInventoryExportV3: const bool.fromEnvironment(
          'ASSET_DESK_ENABLE_EXPORT_V3',
        ),
        enableAssetCheck: const bool.fromEnvironment(
          'ASSET_DESK_ENABLE_ASSET_CHECK',
        ),
        enableAssetLocation: const bool.fromEnvironment(
          'ASSET_DESK_ENABLE_ASSET_LOCATION',
        ),
        enableAssetDates: const bool.fromEnvironment(
          'ASSET_DESK_ENABLE_ASSET_DATES',
        ),
        importApiBase: api.baseUrl.toString(),
        enableInventoryImportV3: const bool.fromEnvironment(
          'ASSET_DESK_ENABLE_IMPORT_V3',
        ),
        enableInventoryImportV2: const bool.fromEnvironment(
          'ASSET_DESK_ENABLE_IMPORT_V2',
        ),
        enableInventoryImport: const bool.fromEnvironment(
          'ASSET_DESK_ENABLE_IMPORT',
        ),
      ),
    );
  } on ArgumentError {
    runApp(
      const _ConfigurationMessage(
        'Invalid endpoint. Use HTTPS /api/v1 without credentials, query or fragment.',
      ),
    );
  } on FormatException {
    runApp(const _ConfigurationMessage('Invalid API URL configuration.'));
  }
}

class _ConfigurationMessage extends StatelessWidget {
  const _ConfigurationMessage(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(message)),
      ),
    ),
  );
}
