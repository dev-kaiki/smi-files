// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../utils/worktime_rules.dart';

class OsFolderApontamentoResult {
  final DateTime data;
  final String inicioHHmmss;
  final String fimHHmmss;
  final double horas;
  final double horasNormais;
  final double horas50;
  final double horas100;
  final String descricao;
  final String tecnico;

  OsFolderApontamentoResult({
    required this.data,
    required this.inicioHHmmss,
    required this.fimHHmmss,
    required this.horas,
    required this.horasNormais,
    required this.horas50,
    required this.horas100,
    required this.descricao,
    required this.tecnico,
  });
}

class OsFolderApontamentoDialog extends StatefulWidget {
  final DateTime? initialData;
  final TimeOfDay? initialInicio;
  final TimeOfDay? initialFim;
  final String? initialDescricao;
  final String? initialTecnico;

  const OsFolderApontamentoDialog({
    super.key,
    this.initialData,
    this.initialInicio,
    this.initialFim,
    this.initialDescricao,
    this.initialTecnico,
  });

  @override
  State<OsFolderApontamentoDialog> createState() => _OsFolderApontamentoDialogState();
}

class _OsFolderApontamentoDialogState extends State<OsFolderApontamentoDialog> {
  final _formKey = GlobalKey<FormState>();
  DateTime _data = DateTime.now();
  TimeOfDay? _inicio;
  TimeOfDay? _fim;
  final _descCtrl = TextEditingController();
  final _tecCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _data = widget.initialData ?? DateTime.now();
    _inicio = widget.initialInicio;
    _fim = widget.initialFim;
    _descCtrl.text = widget.initialDescricao ?? '';
    _tecCtrl.text = widget.initialTecnico ?? '';
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _tecCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _data = d);
  }

  Future<void> _pickInicio() async {
    final t = await showTimePicker(context: context, initialTime: _inicio ?? const TimeOfDay(hour: 7, minute: 0));
    if (t != null) setState(() => _inicio = t);
  }

  Future<void> _pickFim() async {
    final t = await showTimePicker(context: context, initialTime: _fim ?? const TimeOfDay(hour: 17, minute: 0));
    if (t != null) setState(() => _fim = t);
  }

  String _fmtH(double h) {
    final totalMin = (h * 60).round();
    final hrs = totalMin ~/ 60;
    final min = totalMin % 60;
    return min == 0 ? '${hrs}h' : '${hrs}h${min.toString().padLeft(2, '0')}min';
  }

  WorkTimeBreakdown? get _preview {
    if (_inicio == null || _fim == null) return null;
    try {
      return WorkTimeRules.calculate(data: _data, inicio: _inicio!, fim: _fim!);
    } catch (_) {
      return null;
    }
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_inicio == null || _fim == null) return;

    final breakdown = WorkTimeRules.calculate(data: _data, inicio: _inicio!, fim: _fim!);
    Navigator.of(context).pop(
      OsFolderApontamentoResult(
        data: _data,
        inicioHHmmss: '${_inicio!.hour.toString().padLeft(2, '0')}:${_inicio!.minute.toString().padLeft(2, '0')}:00',
        fimHHmmss: '${_fim!.hour.toString().padLeft(2, '0')}:${_fim!.minute.toString().padLeft(2, '0')}:00',
        horas: breakdown.horasTotais,
        horasNormais: breakdown.horasNormais,
        horas50: breakdown.horas50,
        horas100: breakdown.horas100,
        descricao: _descCtrl.text.trim(),
        tecnico: _tecCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return AlertDialog(
      title: const Text('Apontamento de horas'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Data'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(_data)),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: _pickDate,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Início'),
                  subtitle: Text(_inicio == null ? 'Selecionar' : '${_inicio!.hour.toString().padLeft(2, '0')}:${_inicio!.minute.toString().padLeft(2, '0')}'),
                  onTap: _pickInicio,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fim'),
                  subtitle: Text(_fim == null ? 'Selecionar' : '${_fim!.hour.toString().padLeft(2, '0')}:${_fim!.minute.toString().padLeft(2, '0')}'),
                  onTap: _pickFim,
                ),
                TextFormField(
                  controller: _tecCtrl,
                  decoration: const InputDecoration(labelText: 'Técnico', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o técnico.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Descrição', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: preview == null
                      ? const Text('Selecione início e fim válidos para calcular automaticamente.')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Normais: ${_fmtH(preview.horasNormais)}'),
                            Text('50%: ${_fmtH(preview.horas50)}'),
                            Text('100%: ${_fmtH(preview.horas100)}'),
                            const SizedBox(height: 4),
                            Text('Total: ${_fmtH(preview.horasTotais)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Salvar')),
      ],
    );
  }
}
