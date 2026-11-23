import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../state/workspace_controller.dart';
import '../ui/workspace_page.dart';
import 'theme.dart';
import 'version.dart';

class AmllyEditApp extends StatelessWidget {
  const AmllyEditApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('tr'),
      supportedLocales: const [Locale('tr'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _Bootstrap(),
    );
  }
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late Future<WorkspaceController> _future = WorkspaceController.open();

  void _retry() {
    setState(() {
      _future = WorkspaceController.open();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WorkspaceController>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _StartupError(message: snapshot.error.toString(), onRetry: _retry);
        }
        final controller = snapshot.data;
        if (controller == null) return const _Splash();
        return WorkspacePage(controller: controller);
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(kAppName,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            SizedBox(height: 14),
            SizedBox(width: 120, child: LinearProgressIndicator(minHeight: 2)),
          ],
        ),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.danger, size: 36),
              const SizedBox(height: 12),
              const Text('Çalışma alanı açılamadı', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: onRetry, child: const Text('Tekrar dene')),
            ],
          ),
        ),
      ),
    );
  }
}
