// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/supabase/supabase_manager.dart';
import 'features/auth/login_page.dart';
import 'features/home/home_page.dart';
import 'theme/smi_theme.dart';
import 'utils/smi_routes.dart';
import 'pending/pending_media_store.dart';
import 'services/outbox_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseManager.init();
  await PendingMediaStore.I.init();
  await OutboxService.I.init();
  runApp(const SmiApp());
}

class SmiApp extends StatelessWidget {
  const SmiApp({super.key});

  Route<dynamic> _route(Widget page, {RouteSettings? settings}) {
    return MaterialPageRoute(builder: (_) => page, settings: settings);
  }

  Map<String, dynamic>? _args(RouteSettings settings) {
    final a = settings.arguments;
    if (a is Map<String, dynamic>) return a;
    if (a is Map) return a.map((k, v) => MapEntry(k.toString(), v));
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SMI Arquivos',
      debugShowCheckedModeBanner: false,
      theme: SmiTheme.light(),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [
        Locale('pt', 'BR'),
        Locale('pt'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      initialRoute: SmiRoutes.login,

      onGenerateRoute: (settings) {
        switch (settings.name) {
          case SmiRoutes.login:
            return _route(const LoginPage(), settings: settings);

          case SmiRoutes.home: {
            final args = _args(settings);

            final tecnicoId = args?['tecnicoId'];
            final tecnicoNome = args?['tecnicoNome'];
            final setor = args?['setor'];

            if (tecnicoId is! int || tecnicoNome is! String || setor is! String) {
              return _route(
                const _NotImplementedPage(
                  title: 'Erro de navegação',
                  message:
                  'Argumentos inválidos ao abrir a Home.\n'
                      'Esperado: { tecnicoId:int, tecnicoNome:String, setor:String }',
                ),
                settings: settings,
              );
            }

            return _route(
              HomePage(
                tecnicoId: tecnicoId,
                tecnicoNome: tecnicoNome,
                setor: setor,
              ),
              settings: settings,
            );
          }

          case SmiRoutes.newOsFolder:
          // ✅ Troque esta tela pela sua page real de "Nova OS"
          // Ex.: return _route(NewOsFolderPage(...), settings: settings);
            return _route(
              const _NotImplementedPage(
                title: 'Nova OS',
                message: 'Rota /os/new ainda não está ligada a uma página real.',
              ),
              settings: settings,
            );

          case SmiRoutes.osMedia: {
            final args = _args(settings);
            final osFolderId = args?['osFolderId'];

            if (osFolderId is! String || osFolderId.trim().isEmpty) {
              return _route(
                const _NotImplementedPage(
                  title: 'Mídias da OS',
                  message:
                  'Argumentos inválidos.\n'
                      'Esperado: { osFolderId:String }',
                ),
                settings: settings,
              );
            }

            // ✅ Se você quiser abrir sua OsMediaPage por rota:
            // return _route(OsMediaPage(osFolderId: osFolderId), settings: settings);

            return _route(
              _NotImplementedPage(
                title: 'Mídias da OS',
                message:
                'Rota /os/media recebida com osFolderId=$osFolderId\n'
                    'Se quiser, eu ligo direto na sua OsMediaPage.',
              ),
              settings: settings,
            );
          }

          default:
            return _route(
              _NotImplementedPage(
                title: 'Rota não encontrada',
                message: 'Rota: ${settings.name ?? "(null)"}',
              ),
              settings: settings,
            );
        }
      },
    );
  }
}

class _NotImplementedPage extends StatelessWidget {
  final String title;
  final String message;

  const _NotImplementedPage({
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Text(
            message,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}