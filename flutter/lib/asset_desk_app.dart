import 'dart:async';

import 'package:flutter/material.dart';

import 'api/asset_session.dart';
import 'assets_page.dart';
import 'sign_in_page.dart';

/// Own the account lifecycle and replace the complete private navigator on change.
class AssetDeskApp extends StatefulWidget {
  const AssetDeskApp({
    super.key,
    required this.session,
    this.enableInventoryImport = false,
    this.enableInventoryImportV2 = false,
    this.enableInventoryImportV3 = false,
    this.enableAssetDates = false,
    this.enableAssetLocation = false,
    this.enableAssetCheck = false,
    this.enableInventoryExportV3 = false,
    this.enableSelectionExport = false,
    this.enableSelectionExportV2 = false,
    this.importApiBase = '',
  });
  final String importApiBase;
  final AssetSession session;
  final bool enableInventoryImport;
  final bool enableInventoryImportV2;
  final bool enableInventoryImportV3;
  final bool enableAssetDates;
  final bool enableAssetLocation;
  final bool enableAssetCheck;
  final bool enableInventoryExportV3;
  final bool enableSelectionExport;
  final bool enableSelectionExportV2;
  @override
  State<AssetDeskApp> createState() => _AssetDeskAppState();
}

class _AssetDeskAppState extends State<AssetDeskApp> {
  late StreamSubscription<int> _subscription;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _subscription = widget.session.sessionChanges.listen((_) {
      if (mounted) setState(() => _generation++);
    });
  }

  @override
  void didUpdateWidget(covariant AssetDeskApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      unawaited(_subscription.cancel());
      oldWidget.session.close();
      _generation++;
      _listen();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    widget.session.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.session.account;
    return MaterialApp(
      key: ValueKey(_generation),
      title: 'Asset Desk',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
      ),
      builder: (context, child) => account == null
          ? child!
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('Signed in: ${account.name}'),
                          OutlinedButton(
                            onPressed: widget.session.signOut,
                            child: const Text('Sign out'),
                          ),
                          const Text('Signing out clears unsaved drafts.'),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(child: child!),
              ],
            ),
      home: account == null
          ? SignInPage(session: widget.session)
          : AssetsPage(
              store: widget.session,
              importApiBase: widget.importApiBase,
              enableInventoryImport: widget.enableInventoryImport,
              enableInventoryImportV2: widget.enableInventoryImportV2,
              enableInventoryImportV3: widget.enableInventoryImportV3,
              enableAssetDates: widget.enableAssetDates,
              enableAssetLocation: widget.enableAssetLocation,
              enableAssetCheck: widget.enableAssetCheck,
              enableInventoryExportV3: widget.enableInventoryExportV3,
              enableSelectionExport: widget.enableSelectionExport,
              enableSelectionExportV2: widget.enableSelectionExportV2,
            ),
    );
  }
}
