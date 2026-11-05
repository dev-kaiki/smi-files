// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// lib/utils/setor_access.dart

String normalizeSetor(String? raw) {
  var s = (raw ?? '').trim().toLowerCase();
  if (s.isEmpty) return '';

  s = s
      .replaceAll('-', ' ')
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (s.contains('lab') && s.contains('motor')) return 'lab_motores';
  if (s.contains('lab') && s.contains('eletron')) return 'lab_eletronico';
  if (s.contains('lab') && s.contains('mecan')) return 'lab_mecanico';
  if (s.contains('reforma')) return 'reforma';
  if (s.contains('pintura')) return 'pintura';
  if (s.contains('automa')) return 'automacao';
  if (s.contains('ass') || s.contains('assist')) return 'ass_tecnica';
  if (s.contains('ferram') && s.contains('centro')) return 'ferram_centro';
  if (s.contains('ferram') && s.contains('torno')) return 'ferram_torno';
  if (s.contains('geral') || s.contains('servic')) return 'geral';
  if (s.contains('administr')) return 'administrativo';

  return s.replaceAll(' ', '_');
}

const Set<String> kAllSetores = {
  'lab_mecanico',
  'lab_eletronico',
  'lab_motores',
  'reforma',
  'pintura',
  'automacao',
  'ass_tecnica',
  'ferram_centro',
  'ferram_torno',
  'geral',
  'administrativo',
};

Set<String> visibleSetoresFor(String? raw) {
  final setor = normalizeSetor(raw);
  switch (setor) {
    case 'administrativo':
      return {...kAllSetores};
    case 'lab_eletronico':
      return {'lab_eletronico', 'lab_motores'};
    case 'lab_motores':
      return {'lab_motores', 'lab_eletronico'};
    case 'reforma':
      return {'reforma', 'pintura'};
    case 'pintura':
      return {'pintura', 'reforma'};
    case '':
      return <String>{};
    default:
      return {setor};
  }
}

bool canAccessApp(String? raw) => normalizeSetor(raw).isNotEmpty;


bool isAdministrativo(String? raw) => normalizeSetor(raw) == 'administrativo';

bool canUserSeeOs({required String? userSetor, required String? osSetor}) {
  final userVisible = visibleSetoresFor(userSetor);
  final normalizedOsSetor = normalizeSetor(osSetor);
  if (userVisible.isEmpty || normalizedOsSetor.isEmpty) return false;
  return userVisible.contains(normalizedOsSetor);
}

String setorLabel(String? raw) {
  switch (normalizeSetor(raw)) {
    case 'lab_eletronico':
      return 'Lab Eletrônico';
    case 'lab_mecanico':
      return 'Lab Mecânico';
    case 'lab_motores':
      return 'Lab Motores';
    case 'reforma':
      return 'Reforma';
    case 'pintura':
      return 'Pintura';
    case 'automacao':
      return 'Automação';
    case 'ass_tecnica':
      return 'Assistência Técnica';
    case 'ferram_centro':
      return 'Ferram. Centro';
    case 'ferram_torno':
      return 'Ferram. Torno';
    case 'geral':
      return 'Geral';
    case 'administrativo':
      return 'Administrativo';
    case '':
      return '-';
    default:
      final v = normalizeSetor(raw).replaceAll('_', ' ');
      if (v.isEmpty) return '-';
      return v[0].toUpperCase() + v.substring(1);
  }
}
