// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseManager {
  SupabaseManager._();

  /// Cliente global do Supabase
  static SupabaseClient get client => Supabase.instance.client;

  static bool _initialized = false;

  /// Inicializa o Supabase. Chamada em main()
  /// - Protege contra dupla inicialização
  /// - Timeouts mais amigáveis em redes ruins
  static Future<void> init() async {
    if (_initialized) return;

    // Sem valor padrao de proposito: uma credencial embutida aqui vai junto em
    // todo build e vaza o endpoint do banco. Passe no build:
    //   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
    const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
    const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

    if (supabaseUrl.trim().isEmpty || supabaseAnonKey.trim().isEmpty) {
      throw StateError('SUPABASE_URL e SUPABASE_ANON_KEY não configurados.');
    }

    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
      realtimeClientOptions: const RealtimeClientOptions(
        eventsPerSecond: 10,
      ),
      storageOptions: const StorageClientOptions(
        retryAttempts: 3,
      ),
    ).timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw TimeoutException(
        'Tempo esgotado ao conectar no Supabase. Verifique sua internet e tente novamente.',
      ),
    );

    _initialized = true;
  }

  /// Sessão atual (se logado)
  static Session? get session => client.auth.currentSession;

  /// Usuário atual (se logado)
  static User? get user => client.auth.currentUser;

  /// Stream de mudanças de autenticação (login/logout/refresh)
  static Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;

  /// Desloga com segurança
  static Future<void> signOut() async {
    try {
      await client.auth.signOut();
    } catch (_) {
      // não quebra o app em caso de erro de rede
    }
  }
}
