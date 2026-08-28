// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../../core/supabase/supabase_manager.dart';

class SupabaseDiagnosticsPage extends StatefulWidget {
  const SupabaseDiagnosticsPage({super.key});

  @override
  State<SupabaseDiagnosticsPage> createState() => _SupabaseDiagnosticsPageState();
}

class _DiagStep {
  final String title;
  final bool ok;
  final String detail;

  const _DiagStep({required this.title, required this.ok, required this.detail});
}

class _SupabaseDiagnosticsPageState extends State<SupabaseDiagnosticsPage> {
  final List<_DiagStep> _steps = [];
  bool _running = false;
  String? _summary;

  @override
  void initState() {
    super.initState();
    _run();
  }

  void _addStep(String title, bool ok, String detail) {
    if (!mounted) return;
    setState(() {
      _steps.add(_DiagStep(title: title, ok: ok, detail: detail));
    });
  }

  String _fmtError(Object e) => e.toString().trim().replaceAll('\n', ' | ');

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _steps.clear();
      _summary = null;
    });

    final client = SupabaseManager.client;
    final uuid = const Uuid();
    String? tempStoragePath;
    String? tempMediaId;
    String? testOsFolderId;

    try {
      final user = client.auth.currentUser;
      final session = client.auth.currentSession;
      _addStep(
        'Sessão/Auth do app',
        user != null,
        user != null
            ? 'Usuário autenticado: ${user.id} | email=${user.email ?? '-'}'
            : 'Sem usuário autenticado no Supabase Auth. O app está operando com anon key.',
      );
      _addStep(
        'Token de sessão',
        session != null,
        session != null ? 'Access token presente.' : 'Nenhuma sessão ativa retornada pelo SDK.',
      );

      try {
        final row = await client.from('tecnicos').select('id, nome, codigo').limit(1).maybeSingle();
        _addStep(
          'Leitura da tabela tecnicos',
          row != null,
          row == null ? 'Nenhum técnico retornado.' : 'OK. Técnico exemplo: ${row['codigo'] ?? '-'} - ${row['nome'] ?? '-'}',
        );
      } catch (e) {
        _addStep('Leitura da tabela tecnicos', false, _fmtError(e));
      }

      Map<String, dynamic>? osFolder;
      try {
        osFolder = await client
            .from('os_folders')
            .select('id, os_code, ano, storage_prefix')
            .limit(1)
            .maybeSingle();
        testOsFolderId = osFolder == null ? null : osFolder['id']?.toString();
        final prefix = osFolder == null ? '' : (osFolder['storage_prefix'] ?? '').toString();
        _addStep(
          'Leitura da tabela os_folders',
          osFolder != null,
          osFolder == null
              ? 'Nenhuma OS encontrada para teste.'
              : 'OK. OS exemplo: ${osFolder['ano'] ?? '-'} / ${osFolder['os_code'] ?? '-'} | prefix=${prefix.isEmpty ? '(vazio)' : prefix}',
        );
        if (osFolder != null) {
          _addStep(
            'storage_prefix da OS de teste',
            prefix.isNotEmpty,
            prefix.isNotEmpty ? 'Prefixo disponível para mídia.' : 'A OS encontrada não tem storage_prefix preenchido.',
          );
        }
      } catch (e) {
        _addStep('Leitura da tabela os_folders', false, _fmtError(e));
      }

      try {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/smi_diag_${DateTime.now().microsecondsSinceEpoch}.txt');
        await file.writeAsString('SMI FILES SUPABASE DIAGNOSTIC ${DateTime.now().toIso8601String()}');
        tempStoragePath = 'diagnostico_app/${DateTime.now().year}/${uuid.v4()}.txt';

        await client.storage.from('smi_midias').upload(
          tempStoragePath,
          file,
          fileOptions: const FileOptions(upsert: true, contentType: 'text/plain'),
        );

        final signedUrl = await client.storage.from('smi_midias').createSignedUrl(tempStoragePath, 300);
        _addStep(
          'Upload no bucket smi_midias',
          true,
          'Upload concluído em $tempStoragePath | signedUrl gerada=${signedUrl.isNotEmpty}',
        );
      } catch (e) {
        _addStep('Upload no bucket smi_midias', false, _fmtError(e));
      }

      if (testOsFolderId != null && tempStoragePath != null) {
        try {
          tempMediaId = uuid.v4();
          await client.from('media_files').insert({
            'id': tempMediaId,
            'os_folder_id': testOsFolderId,
            'file_type': 'file',
            'storage_path': tempStoragePath,
            'is_cover': false,
          });
          _addStep(
            'Insert em media_files',
            true,
            'Insert temporário aceito para os_folder_id=$testOsFolderId',
          );
        } catch (e) {
          _addStep('Insert em media_files', false, _fmtError(e));
        }
      } else {
        _addStep(
          'Insert em media_files',
          false,
          'Teste ignorado porque faltou os_folder_id válido ou upload prévio no Storage.',
        );
      }
    } finally {
      if (tempMediaId != null) {
        try {
          await client.from('media_files').delete().eq('id', tempMediaId);
          _addStep('Limpeza do media_files de teste', true, 'Registro temporário removido.');
        } catch (e) {
          _addStep('Limpeza do media_files de teste', false, _fmtError(e));
        }
      }

      if (tempStoragePath != null) {
        try {
          await client.storage.from('smi_midias').remove([tempStoragePath]);
          _addStep('Limpeza do Storage de teste', true, 'Arquivo temporário removido do bucket.');
        } catch (e) {
          _addStep('Limpeza do Storage de teste', false, _fmtError(e));
        }
      }

      final okCount = _steps.where((e) => e.ok).length;
      final failCount = _steps.length - okCount;
      if (mounted) {
        setState(() {
          _running = false;
          _summary = 'Concluído. Etapas OK: $okCount | Falhas: $failCount';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teste do Supabase'),
        actions: [
          IconButton(
            tooltip: 'Executar novamente',
            onPressed: _running ? null : _run,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Este teste usa o mesmo cliente Supabase do app.',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ele valida sessão/Auth, leitura de tabelas, upload no bucket smi_midias e insert temporário em media_files.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                Text(_summary ?? (_running ? 'Executando diagnóstico...' : 'Pronto para executar.')),
              ],
            ),
          ),
          Expanded(
            child: _steps.isEmpty && _running
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: _steps.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final step = _steps[i];
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: step.ok ? Colors.green.shade300 : cs.error.withOpacity(0.45),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              step.ok ? Icons.check_circle : Icons.error_outline,
                              color: step.ok ? Colors.green.shade700 : cs.error,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(step.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 6),
                                  SelectableText(step.detail),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
