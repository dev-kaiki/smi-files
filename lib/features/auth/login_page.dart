// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// lib/features/auth/login_page.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/supabase/supabase_manager.dart';
import '../../utils/setor_access.dart';
import '../../utils/smi_routes.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _codigoCtrl = TextEditingController();
  final TextEditingController _senhaCtrl = TextEditingController();

  final FocusNode _codigoFocus = FocusNode();
  final FocusNode _senhaFocus = FocusNode();

  bool _isLoading = false;
  bool _rememberMe = false;
  bool _checkingAutoLogin = true; // enquanto checa prefs, mostra loading
  bool _showPassword = false;


  @override
  void initState() {
    super.initState();
    _tryAutoLogin();
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _senhaCtrl.dispose();
    _codigoFocus.dispose();
    _senhaFocus.dispose();
    super.dispose();
  }

  // ==========================
  // AUTO LOGIN (REMEMBER-ME)
  // ==========================

  Future<void> _tryAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final remember = prefs.getBool('remember_me') ?? false;
      final savedId = prefs.getInt('tecnico_id');
      final savedNome = prefs.getString('tecnico_nome');
      final savedSetor = prefs.getString('tecnico_setor');

      if (remember && savedId != null && savedNome != null && savedSetor != null) {
        final setorNormalizado = normalizeSetor(savedSetor);

        // se o setor salvo NÃO tiver mais acesso, volta pra tela de login normal
        if (!canAccessApp(setorNormalizado)) {
          if (!mounted) return;
          setState(() {
            _checkingAutoLogin = false;
            _rememberMe = false;
          });
          return;
        }

        // setor ok → vai direto pro home
        if (!mounted) return;
        Navigator.pushReplacementNamed(
          context,
          SmiRoutes.home,
          arguments: {
            'tecnicoId': savedId,
            'tecnicoNome': savedNome,
            'setor': setorNormalizado,
          },
        );
      } else {
        if (!mounted) return;
        setState(() {
          _checkingAutoLogin = false;
          _rememberMe = remember;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checkingAutoLogin = false;
        _rememberMe = false;
      });
    }
  }

  Future<void> _saveRememberedUser({
    required bool remember,
    required int tecnicoId,
    required String tecnicoNome,
    required String setor,
    required String tecnicoCodigo,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    if (remember) {
      await prefs.setBool('remember_me', true);
      await prefs.setInt('tecnico_id', tecnicoId);
      await prefs.setString('tecnico_nome', tecnicoNome);
      await prefs.setString('tecnico_setor', setor);
      await prefs.setString('tecnico_codigo', tecnicoCodigo);
    } else {
      // se desmarcar, limpa apenas o remember-me
      await prefs.remove('remember_me');
      await prefs.remove('tecnico_id');
      await prefs.remove('tecnico_nome');
      await prefs.remove('tecnico_setor');
      await prefs.remove('tecnico_codigo');
    }
  }

  Future<void> _saveCurrentSessionUser({
    required int tecnicoId,
    required String tecnicoNome,
    required String setor,
    required String tecnicoCodigo,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('current_tecnico_id', tecnicoId);
    await prefs.setString('current_tecnico_nome', tecnicoNome);
    await prefs.setString('current_tecnico_setor', setor);
    await prefs.setString('current_tecnico_codigo', tecnicoCodigo);
  }

  // ==========================
  // LOGIN
  // ==========================

  void _hideKeyboard() {
    FocusScope.of(context).unfocus();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _login() async {
    if (_isLoading) return;
    _hideKeyboard();

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final codigo = _codigoCtrl.text.trim();
      final senha = _senhaCtrl.text.trim();

      // V9.4 FIX: usa RPC app_login_tecnico em vez de query direta com
      // .eq('senha', senha). A query direta expunha a senha como parâmetro
      // de URL nos logs do Supabase (?senha=eq.VALOR). A RPC valida no banco
      // e nunca expõe a senha em query string.
      final List<dynamic> rows = await SupabaseManager.client
          .rpc('app_login_tecnico', params: {
            'p_codigo': codigo,
            'p_senha': senha,
          })
          .timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw TimeoutException('Tempo esgotado ao conectar.'),
      );

      if (rows.isEmpty) {
        _showSnack('Código ou senha inválidos.');
        return;
      }

      final resp = rows.first as Map<String, dynamic>;

      final tecnicoId = resp['id'] as int;
      final tecnicoNome = (resp['nome'] ?? 'Técnico').toString();
      final tecnicoCodigo = (resp['codigo'] ?? codigo).toString().trim();
      final setorRaw = (resp['setor'] ?? 'Setor').toString();
      final setorNormalizado = normalizeSetor(setorRaw);

      // valida se o setor tem acesso
      if (!canAccessApp(setorNormalizado)) {
        _showSnack('Seu usuário está sem setor válido para acessar o app.');
        return;
      }

      await _saveCurrentSessionUser(
        tecnicoId: tecnicoId,
        tecnicoNome: tecnicoNome,
        setor: setorNormalizado,
        tecnicoCodigo: tecnicoCodigo,
      );

      // salva ou não, dependendo do checkbox
      await _saveRememberedUser(
        remember: _rememberMe,
        tecnicoId: tecnicoId,
        tecnicoNome: tecnicoNome,
        setor: setorNormalizado,
        tecnicoCodigo: tecnicoCodigo,
      );

      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        SmiRoutes.home,
        arguments: {
          'tecnicoId': tecnicoId,
          'tecnicoNome': tecnicoNome,
          'setor': setorNormalizado,
        },
      );
    } catch (e) {
      _showSnack('Erro ao fazer login: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==========================
  // BUILD
  // ==========================

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_checkingAutoLogin) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF4F5454),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFF5FAF3),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo + título
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C853).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(
                        Icons.folder_special,
                        size: 42,
                        color: Color(0xFF00C853),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'SMI Arquivos',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Acesse com seu código e senha',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 22),

                    // Código
                    TextFormField(
                      controller: _codigoCtrl,
                      focusNode: _codigoFocus,
                      enabled: !_isLoading,
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) => _senhaFocus.requestFocus(),
                      decoration: InputDecoration(
                        labelText: 'Código do técnico',
                        prefixIcon: const Icon(Icons.badge),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (v) {
                        if ((v ?? '').trim().isEmpty) return 'Informe o código';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Senha
                    TextFormField(
                      controller: _senhaCtrl,
                      focusNode: _senhaFocus,
                      enabled: !_isLoading,
                      obscureText: !_showPassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _login(),
                      decoration: InputDecoration(
                        labelText: 'Senha',
                        prefixIcon: const Icon(Icons.lock),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        suffixIcon: IconButton(
                          tooltip: _showPassword ? 'Ocultar senha' : 'Mostrar senha',
                          onPressed: _isLoading ? null : () => setState(() => _showPassword = !_showPassword),
                          icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                        ),
                      ),
                      validator: (v) {
                        if ((v ?? '').trim().isEmpty) return 'Informe a senha';
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),

                    // LEMBRAR-ME
                    //
                    // O Material transparente nao e enfeite. O cartao de login
                    // e um Container com BoxDecoration opaca, e o ListTile
                    // pinta fundo e ondulacao de toque no Material mais
                    // proximo — que aqui esta ACIMA do Container. Sem este
                    // Material no meio, o fundo do cartao cobre o efeito e o
                    // checkbox nao responde visualmente ao toque.
                    Material(
                      type: MaterialType.transparency,
                      child: CheckboxListTile(
                        value: _rememberMe,
                        onChanged: _isLoading
                            ? null
                            : (value) {
                          setState(() => _rememberMe = value ?? false);
                        },
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('Lembrar-me'),
                        subtitle: Text(
                          'Entrar automaticamente neste aparelho',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Botão login
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: _isLoading
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : const Icon(Icons.login),
                        label: Text(
                          _isLoading ? 'Entrando...' : 'Entrar',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00C853),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 0,
                        ),
                        onPressed: _isLoading ? null : _login,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
