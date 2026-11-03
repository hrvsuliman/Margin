import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';

import 'data/store.dart';
import 'sync/sync_client.dart';
import 'ui/home.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final folder = await getApplicationSupportDirectory();
  Services.store = await Store.load(File('${folder.path}${Platform.pathSeparator}margin-data.json'));
  Services.sync = SyncClient(Services.store, File('${folder.path}${Platform.pathSeparator}sync.json'));
  await Services.sync.load();
  runApp(const MarginApp());
}

class MarginApp extends StatefulWidget {
  const MarginApp({super.key});

  @override
  State<MarginApp> createState() => _MarginAppState();
}

class _MarginAppState extends State<MarginApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Save right away when the app goes to the background, sync when it comes back.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) Services.store.flush();
    if (state == AppLifecycleState.resumed) Services.sync.syncNow();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Margin',
        debugShowCheckedModeBanner: false,
        theme: marginTheme(Brightness.light),
        darkTheme: marginTheme(Brightness.dark),
        locale: const Locale('de'),
        supportedLocales: const [Locale('de')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const HomeShell(),
      );
}
