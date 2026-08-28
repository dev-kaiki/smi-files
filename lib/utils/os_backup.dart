// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// lib/utils/os_backup.dart

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/supabase/supabase_manager.dart';

class OsBackup {
  OsBackup._();

  /// Faz backup de todas as pastas de OS do banco,
  /// baixando as mídias e organizando no disco local.
  ///
  /// Estrutura:
  ///   pastaEscolhida/smi/clientes/<cliente>/Ano/<ano>/Setor/<setor>/OS_<ano>_<codigo>/
  ///     ├─ imagens/
  ///     ├─ videos/
  ///     ├─ pdfs/
  ///     └─ arquivos/
  static Future<void> backupAllOs(BuildContext context) async {
    // 1) Usuário escolhe a pasta base do backup
    final outputDirPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Escolha a pasta para salvar o backup das OS',
      lockParentWindow: false,
    );

    if (outputDirPath == null) return; // cancelou

    // 2) Buscar todas as OS + cliente
    List<Map<String, dynamic>> osList;
    try {
      final resp = await SupabaseManager.client
          .from('os_folders')
          .select('''
            id,
            ano,
            os_code,
            tipo,
            setor,
            storage_prefix,
            clientes ( razao_social )
          ''')
          .order('created_at', ascending: false);

      osList = (resp as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Erro ao carregar OS para backup: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar OS para backup: $e')),
        );
      }
      return;
    }

    if (osList.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhuma OS encontrada para backup.')),
        );
      }
      return;
    }

    // Log file (timestamp)
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

    final logDir = Directory(p.join(outputDirPath, 'smi'));
    if (!await logDir.exists()) await logDir.create(recursive: true);

    final logFile = File(p.join(logDir.path, 'backup_log_$stamp.txt'));
    Future<void> log(String line) async {
      try {
        await logFile.writeAsString('${DateTime.now().toIso8601String()}  $line\n',
            mode: FileMode.append, flush: true);
      } catch (_) {}
    }

    await log('=== INÍCIO BACKUP OS ===');
    await log('Destino: $outputDirPath');
    await log('Total OS: ${osList.length}');

    // Contadores
    int totalOsProcessadas = 0;
    int totalFilesOk = 0;
    int totalFileErrors = 0;
    int totalOsComErro = 0;

    // Progresso UI
    bool cancelled = false;
    int idx = 0;
    String currentOsLabel = '';
    String currentStep = 'Iniciando...';

    void closeProgressDialog() {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
    }

    // Abre modal de progresso
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setDlg) {
              // função local para atualizar UI do diálogo
              void updateDialog() => setDlg(() {});
              // armazena numa closure pra usar dentro do loop
              _progressUpdate = (String osLabel, String step, int i) {
                currentOsLabel = osLabel;
                currentStep = step;
                idx = i;
                if (ctx.mounted) updateDialog();
              };
              _progressSetCounts = () {
                if (ctx.mounted) updateDialog();
              };

              return WillPopScope(
                onWillPop: () async => false,
                child: AlertDialog(
                  title: const Text('Backup em andamento'),
                  content: SizedBox(
                    width: double.maxFinite,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'OS: ${idx + 1} / ${osList.length}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: osList.isEmpty ? null : (idx + 1) / osList.length,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        const SizedBox(height: 12),
                        if (currentOsLabel.trim().isNotEmpty)
                          Text(
                            currentOsLabel,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        const SizedBox(height: 8),
                        Text(
                          currentStep,
                          style: const TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _miniStat('OK', totalFilesOk.toString(), Icons.check_circle, Colors.green),
                            _miniStat('Erros', totalFileErrors.toString(), Icons.error, Colors.red),
                            _miniStat('OS c/ erro', totalOsComErro.toString(), Icons.warning_amber, Colors.orange),
                          ],
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton.icon(
                      onPressed: cancelled
                          ? null
                          : () {
                        cancelled = true;
                        updateDialog();
                      },
                      icon: const Icon(Icons.stop_circle),
                      label: Text(cancelled ? 'Cancelando...' : 'Cancelar'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    }

    // 3) Para cada OS, baixar as mídias
    for (final os in osList) {
      if (cancelled) {
        await log('Backup cancelado pelo usuário.');
        break;
      }

      final osId = os['id'].toString();
      final ano = (os['ano'] ?? '').toString();
      final osCode = (os['os_code'] ?? '').toString();
      final setor = (os['setor'] ?? '').toString();

      final clienteNome = _safeClienteNome(os);
      final clienteFolderName =
      _sanitizePathSegment(clienteNome.trim().isEmpty ? 'Sem_cliente' : clienteNome);

      final anoFolder = ano.isEmpty ? 'sem_ano' : _sanitizePathSegment(ano);
      final setorFolder = setor.isEmpty ? 'sem_setor' : _sanitizePathSegment(setor);
      final osFolderName = osCode.isEmpty ? 'OS_$anoFolder' : 'OS_${anoFolder}_$osCode';

      final osDir = Directory(
        p.join(
          outputDirPath,
          'smi',
          'clientes',
          clienteFolderName,
          'Ano',
          anoFolder,
          'Setor',
          setorFolder,
          osFolderName,
        ),
      );

      if (!await osDir.exists()) {
        await osDir.create(recursive: true);
      }

      // atualiza dialog
      _progressUpdate?.call(
        'OS $ano/$osCode • $clienteNome',
        'Listando mídias...',
        idx,
      );

      bool teveErroNestaOs = false;

      // Listar mídias da OS
      List<Map<String, dynamic>> mediaList = [];
      try {
        final mediaResp = await SupabaseManager.client
            .from('media_files')
            .select('storage_path, file_type')
            .eq('os_folder_id', osId);

        mediaList = (mediaResp as List).cast<Map<String, dynamic>>();
      } catch (e) {
        teveErroNestaOs = true;
        totalOsComErro++;
        await log('ERRO listar mídias OS=$osId: $e');
        debugPrint('Falha ao listar mídias da OS $osId: $e');
        idx++;
        _progressUpdate?.call('OS $ano/$osCode • $clienteNome', 'Falha ao listar mídias (pulando).', idx);
        continue;
      }

      // baixa mídias
      for (final m in mediaList) {
        if (cancelled) break;

        final storagePath = (m['storage_path'] ?? '').toString();
        if (storagePath.isEmpty) continue;

        final fileType = (m['file_type'] ?? '').toString();
        final typeFolder = _typeFolder(fileType);

        final destDir = Directory(p.join(osDir.path, typeFolder));
        if (!await destDir.exists()) {
          await destDir.create(recursive: true);
        }

        final fileName = p.basename(storagePath);
        final safeFileName = _sanitizeFileName(fileName);

        _progressUpdate?.call(
          'OS $ano/$osCode • $clienteNome',
          'Baixando: $safeFileName',
          idx,
        );

        try {
          final bytes = await SupabaseManager.client.storage
              .from('smi_midias')
              .download(storagePath);

          final destFile = await _uniqueFilePath(destDir.path, safeFileName);
          await File(destFile).writeAsBytes(bytes, flush: true);

          totalFilesOk++;
          _progressSetCounts?.call();
        } catch (e) {
          totalFileErrors++;
          teveErroNestaOs = true;
          _progressSetCounts?.call();
          await log('ERRO download OS=$osId path=$storagePath: $e');
          debugPrint('Falha ao baixar $storagePath: $e');
        }
      }

      totalOsProcessadas++;
      if (teveErroNestaOs) totalOsComErro++;

      idx++;
      _progressUpdate?.call(
        'OS $ano/$osCode • $clienteNome',
        cancelled ? 'Cancelando...' : 'Concluída.',
        idx,
      );
    }

    // fecha modal progresso
    if (context.mounted) {
      try {
        closeProgressDialog();
      } catch (_) {}
    }

    await log('=== FIM BACKUP OS ===');
    await log('Processadas: $totalOsProcessadas');
    await log('Arquivos OK: $totalFilesOk');
    await log('Arquivos com erro: $totalFileErrors');
    await log('OS com erro: $totalOsComErro');
    await log('Cancelado: $cancelled');
    await log('Log: ${logFile.path}');

    // SnackBar final
    if (context.mounted) {
      String msg;
      if (cancelled) {
        msg = 'Backup cancelado. Parcial salvo: $totalOsProcessadas OS, $totalFilesOk arquivos OK.';
      } else if (totalOsProcessadas == 0 && totalFilesOk == 0) {
        msg = 'Backup não concluiu (nenhum arquivo salvo). Verifique a conexão.';
      } else if (totalFileErrors > 0 || totalOsComErro > 0) {
        msg =
        'Backup concluído com avisos: $totalOsProcessadas OS, $totalFilesOk arquivos OK, $totalFileErrors falharam.';
      } else {
        msg = 'Backup concluído: $totalOsProcessadas OS e $totalFilesOk arquivos de mídia.';
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Log gerado: ${p.basename(logFile.path)}')),
      );
    }

    // Se cancelou, não pergunta apagar
    if (cancelled) return;

    // Perguntar se deseja apagar as pastas do banco
    await _perguntarApagarAposBackup(context, osList);
  }

  // ====== UI helpers (dialog stats) ======
  static Widget _miniStat(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text('$title: ', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
          Text(value, style: TextStyle(fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }

  // callbacks para atualizar dialog (setadas em runtime)
  static void Function(String osLabel, String step, int idx)? _progressUpdate;
  static void Function()? _progressSetCounts;

  // =========================
  // PERGUNTAR SOBRE EXCLUSÃO
  // =========================

  static Future<void> _perguntarApagarAposBackup(
      BuildContext context,
      List<Map<String, dynamic>> osList,
      ) async {
    if (osList.isEmpty) return;

    final choice = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backup concluído'),
        content: const Text(
          'O backup de todas as pastas foi concluído.\n\n'
              'O que você deseja fazer com as pastas de OS no banco de dados?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 0),
            child: const Text('Manter todas'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 2),
            child: const Text('Escolher quais apagar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 1),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Apagar todas'),
          ),
        ],
      ),
    );

    if (choice == null || choice == 0) return;

    if (choice == 1) {
      // confirmação forte
      final confirm = await _confirmTypedDeleteAll(context);
      if (!confirm) return;

      final ids = osList.map((o) => o['id'].toString()).toList();
      await _apagarOsPorIds(context, ids);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Todas as pastas de OS foram apagadas do banco.')),
        );
      }
      return;
    }

    if (choice == 2) {
      await _dialogEscolherQuaisApagar(context, osList);
    }
  }

  static Future<bool> _confirmTypedDeleteAll(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmação necessária'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Você escolheu APAGAR TODAS as pastas do banco (e mídias do storage).\n\n'
                  'Digite APAGAR para confirmar.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Digite APAGAR',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim().toUpperCase() == 'APAGAR'),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return ok == true;
  }

  static Future<void> _dialogEscolherQuaisApagar(
      BuildContext context,
      List<Map<String, dynamic>> osList,
      ) async {
    final selecionados = <String>{};

    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: const Text('Escolha as OS para apagar'),
              content: SizedBox(
                width: double.maxFinite,
                height: 420,
                child: ListView.builder(
                  itemCount: osList.length,
                  itemBuilder: (_, index) {
                    final os = osList[index];
                    final id = os['id'].toString();
                    final ano = (os['ano'] ?? '').toString();
                    final osCode = (os['os_code'] ?? '').toString();
                    final setor = (os['setor'] ?? '').toString();
                    final cliente = _safeClienteNome(os);

                    final title = 'OS $ano/$osCode';
                    final subtitle =
                    [cliente, setor].where((e) => e.trim().isNotEmpty).join(' · ');

                    final checked = selecionados.contains(id);

                    return CheckboxListTile(
                      value: checked,
                      title: Text(title),
                      subtitle: subtitle.isEmpty ? null : Text(subtitle),
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            selecionados.add(id);
                          } else {
                            selecionados.remove(id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: selecionados.isEmpty ? null : () => Navigator.pop(ctx, Set<String>.from(selecionados)),
                  child: const Text('Apagar selecionadas'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || result.isEmpty) return;

    await _apagarOsPorIds(context, result.toList());

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pastas selecionadas apagadas do banco com sucesso.')),
      );
    }
  }

  // =========================
  // APAGAR OS + MÍDIAS
  // =========================

  static Future<void> _apagarOsPorIds(
      BuildContext context,
      List<String> osIds,
      ) async {
    for (final osId in osIds) {
      try {
        // Buscar caminhos das mídias dessa OS
        final mediaResp = await SupabaseManager.client
            .from('media_files')
            .select('storage_path')
            .eq('os_folder_id', osId);

        final mediaList = (mediaResp as List).cast<Map<String, dynamic>>();
        final paths = mediaList
            .map((m) => (m['storage_path'] ?? '').toString())
            .where((p) => p.isNotEmpty)
            .toList();

        if (paths.isNotEmpty) {
          // Remover do storage
          await SupabaseManager.client.storage.from('smi_midias').remove(paths);
        }

        // Remover registros de media_files
        await SupabaseManager.client.from('media_files').delete().eq('os_folder_id', osId);

        // Remover a OS
        await SupabaseManager.client.from('os_folders').delete().eq('id', osId);
      } catch (e) {
        debugPrint('Erro ao apagar OS $osId: $e');
        // não aborta geral
      }
    }
  }

  // =========================
  // HELPERS
  // =========================

  static String _safeClienteNome(Map<String, dynamic> os) {
    final embedded = os['clientes'];
    if (embedded is Map) {
      return (embedded['razao_social'] ?? '').toString();
    }
    if (embedded is List && embedded.isNotEmpty) {
      final first = embedded.first;
      if (first is Map) {
        return (first['razao_social'] ?? '').toString();
      }
    }
    return '';
  }

  static String _typeFolder(String rawType) {
    final t = rawType.trim().toLowerCase();
    if (t.contains('video')) return 'videos';
    if (t.contains('image') || t.contains('foto') || t.contains('img')) return 'imagens';
    if (t.contains('pdf')) return 'pdfs';
    return 'arquivos';
  }

  static String _sanitizeFileName(String input) {
    var s = input.trim();
    const invalid = r'<>:"/\|?*';
    for (final ch in invalid.split('')) {
      s = s.replaceAll(ch, '_');
    }
    if (s.isEmpty) return 'arquivo';
    if (s.length > 120) s = s.substring(0, 120);
    return s;
  }

  static Future<String> _uniqueFilePath(String dirPath, String fileName) async {
    final base = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);

    var candidate = p.join(dirPath, fileName);
    var n = 2;

    while (await File(candidate).exists()) {
      candidate = p.join(dirPath, '${base}_$n$ext');
      n++;
      if (n > 9999) break;
    }

    return candidate;
  }

  /// Sanitiza um segmento de caminho (nome de pasta/arquivo) removendo
  /// caracteres inválidos para o sistema de arquivos.
  static String _sanitizePathSegment(String input) {
    var s = input.trim();

    const invalid = r'<>:"/\|?*';
    for (final ch in invalid.split('')) {
      s = s.replaceAll(ch, '_');
    }

    if (s.isEmpty) return 'sem_nome';
    if (s.length > 60) s = s.substring(0, 60);

    return s;
  }
}
