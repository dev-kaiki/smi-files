// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// lib/utils/worktime_calc.dart
//
// Cálculo de horas (normal / 50% / 100%) com:
//
// - Jornada padrão: Seg-Sex 07:00–17:00 (normal)
// - Seg-Sex fora da janela: 50%
// - Sábado: 50% (se NÃO for feriado)
// - Domingo: 100%
// - Feriado (qualquer dia): 100%
//
// Almoço:
// - Desconto opcional do intervalo 12:00–13:00 (padrão), aplicado apenas se houver sobreposição
//   entre o apontamento e o intervalo de almoço.
//
// OBS: feriados podem ser sobrescritos via arquivo JSON externo (ver readHolidayOverrides)

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class HolidayHit {
  final String dateYmd; // yyyy-MM-dd
  final String name;

  HolidayHit({required this.dateYmd, required this.name});

  Map<String, dynamic> toJson() => {'date': dateYmd, 'name': name};
}

class WorktimeCalcResult {
  final int minutesNormais;
  final int minutes50;
  final int minutes60; // reservado (mantido por compatibilidade)
  final int minutes100;
  final int lunchMinutesApplied;
  final List<HolidayHit> holidays;

  const WorktimeCalcResult({
    required this.minutesNormais,
    required this.minutes50,
    required this.minutes60,
    required this.minutes100,
    required this.lunchMinutesApplied,
    required this.holidays,
  });

  int get minutesTotal => minutesNormais + minutes50 + minutes60 + minutes100;

  double get hNormais => minutesNormais / 60.0;
  double get h50 => minutes50 / 60.0;
  double get h60 => minutes60 / 60.0;
  double get h100 => minutes100 / 60.0;
  double get hTotal => minutesTotal / 60.0;

  Map<String, dynamic> toJson() => {
    'minutes': {
      'normais': minutesNormais,
      'h50': minutes50,
      'h60': minutes60,
      'h100': minutes100,
      'total': minutesTotal,
      'lunch_applied': lunchMinutesApplied,
    },
    'hours': {
      'normais': hNormais,
      'h50': h50,
      'h60': h60,
      'h100': h100,
      'total': hTotal,
    },
    'holidays': holidays.map((e) => e.toJson()).toList(),
  };
}

class WorktimeRules {
  /// Jornada padrão
  final int workStartMinutes; // 07:00 => 420
  final int workEndMinutes; // 17:00 => 1020

  /// Almoço padrão (desconto)
  final int lunchStartMinutes; // 12:00 => 720
  final int lunchEndMinutes; // 13:00 => 780

  const WorktimeRules({
    this.workStartMinutes = 7 * 60,
    this.workEndMinutes = 17 * 60,
    this.lunchStartMinutes = 12 * 60,
    this.lunchEndMinutes = 13 * 60,
  });

  Map<String, dynamic> toJson() => {
    'work_start': _mmToHHmm(workStartMinutes),
    'work_end': _mmToHHmm(workEndMinutes),
    'lunch_start': _mmToHHmm(lunchStartMinutes),
    'lunch_end': _mmToHHmm(lunchEndMinutes),
  };
}

/// Lê feriados customizados de um arquivo externo.
///
/// Caminho: <Documents>/smi_outbox/feriados_override.json
///
/// Formatos aceitos:
/// 1) Lista: [{"date":"2026-04-21","name":"Tiradentes"}, ...]
/// 2) Mapa: {"2026-04-21":"Tiradentes", ...}
Future<Map<String, String>> readHolidayOverrides() async {
  try {
    final docs = await getApplicationDocumentsDirectory();
    final file = File(p.join(docs.path, 'smi_outbox', 'feriados_override.json'));
    if (!await file.exists()) return {};
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return {};
    final decoded = jsonDecode(raw);

    final out = <String, String>{};

    if (decoded is Map) {
      for (final entry in decoded.entries) {
        final k = entry.key.toString().trim();
        final v = entry.value?.toString().trim() ?? '';
        if (_isYmd(k) && v.isNotEmpty) out[k] = v;
      }
      return out;
    }

    if (decoded is List) {
      for (final e in decoded) {
        if (e is Map) {
          final date = (e['date'] ?? e['data'] ?? '').toString().trim();
          final name = (e['name'] ?? e['nome'] ?? '').toString().trim();
          if (_isYmd(date) && name.isNotEmpty) out[date] = name;
        }
      }
      return out;
    }

    return {};
  } catch (_) {
    return {};
  }
}

/// Retorna nome do feriado (ou null se não for feriado).
///
/// - overrides (arquivo) tem prioridade.
/// - depois aplica feriados nacionais fixos e móveis mais comuns.
String? holidayNameBR(DateTime date, Map<String, String> overrides) {
  final ymd = _toYmd(date);
  if (overrides.containsKey(ymd)) return overrides[ymd];

  // Feriados nacionais fixos
  final fixed = <String, String>{
    '${date.year}-01-01': 'Confraternização Universal',
    '${date.year}-04-21': 'Tiradentes',
    '${date.year}-05-01': 'Dia do Trabalhador',
    '${date.year}-09-07': 'Independência do Brasil',
    '${date.year}-10-12': 'Nossa Senhora Aparecida',
    '${date.year}-11-02': 'Finados',
    '${date.year}-11-15': 'Proclamação da República',
    '${date.year}-12-25': 'Natal',
  };
  if (fixed.containsKey(ymd)) return fixed[ymd];

  // Feriados móveis (muito usados no Brasil)
  final easter = _easterSunday(date.year);

  final goodFriday = easter.subtract(const Duration(days: 2));
  if (_sameDay(date, goodFriday)) return 'Sexta-feira Santa';

  final carnavalTue = easter.subtract(const Duration(days: 47));
  if (_sameDay(date, carnavalTue)) return 'Carnaval';

  final carnavalMon = easter.subtract(const Duration(days: 48));
  if (_sameDay(date, carnavalMon)) return 'Carnaval';

  final corpusChristi = easter.add(const Duration(days: 60));
  if (_sameDay(date, corpusChristi)) return 'Corpus Christi';

  return null;
}

/// Calcula minutos por faixa (normal/50/100) para um intervalo.
///
/// Regras:
/// - Seg–Sex (não feriado): normal 07–17; fora disso 50%
/// - Sábado (não feriado): 50%
/// - Domingo: 100%
/// - Feriado (qualquer dia): 100%
///
/// Almoço (opcional): desconta o overlap com 12–13 (ou regra configurada).
WorktimeCalcResult calcWorktime({
  required DateTime start,
  required DateTime end,
  required WorktimeRules rules,
  required Map<String, String> holidayOverrides,
  required bool descontoAlmoco,
}) {
  if (!end.isAfter(start)) {
    return const WorktimeCalcResult(
      minutesNormais: 0,
      minutes50: 0,
      minutes60: 0,
      minutes100: 0,
      lunchMinutesApplied: 0,
      holidays: [],
    );
  }

  var totalN = 0;
  var total50 = 0;
  var total60 = 0;
  var total100 = 0;
  var lunchApplied = 0;
  final holidayHits = <HolidayHit>[];

  DateTime cursor = start;

  while (cursor.isBefore(end)) {
    final dayStart = DateTime(cursor.year, cursor.month, cursor.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final segStart = cursor.isAfter(dayStart) ? cursor : dayStart;
    final segEnd = end.isBefore(dayEnd) ? end : dayEnd;

    final segMinutes = segEnd.difference(segStart).inMinutes;
    if (segMinutes <= 0) {
      cursor = segEnd;
      continue;
    }

    final dow = dayStart.weekday; // 1..7

    final hName = holidayNameBR(dayStart, holidayOverrides);
    final isHoliday = hName != null;

    if (isHoliday) {
      // adiciona 1 vez por dia
      final ymd = _toYmd(dayStart);
      if (!holidayHits.any((h) => h.dateYmd == ymd)) {
        holidayHits.add(HolidayHit(dateYmd: ymd, name: hName!));
      }
    }

    // minutos alocados APENAS para este dia/segmento
    var dayN = 0;
    var day50 = 0;
    var day60 = 0;
    var day100 = 0;

    // classificação do dia
    if (isHoliday) {
      day100 = segMinutes;
    } else if (dow == DateTime.sunday) {
      day100 = segMinutes;
    } else if (dow == DateTime.saturday) {
      day50 = segMinutes;
    } else {
      // Seg–Sex
      final normalStart = dayStart.add(Duration(minutes: rules.workStartMinutes));
      final normalEnd = dayStart.add(Duration(minutes: rules.workEndMinutes));

      final normalOverlap = _overlapMinutes(segStart, segEnd, normalStart, normalEnd);
      final overtime = segMinutes - normalOverlap;

      dayN += normalOverlap;
      if (overtime > 0) day50 += overtime;
    }

    // almoço (desconto) - aplicado somente dentro do intervalo informado
    if (descontoAlmoco) {
      final lunchStart = dayStart.add(Duration(minutes: rules.lunchStartMinutes));
      final lunchEnd = dayStart.add(Duration(minutes: rules.lunchEndMinutes));
      final lunchOverlap = _overlapMinutes(segStart, segEnd, lunchStart, lunchEnd);

      if (lunchOverlap > 0) {
        var remaining = lunchOverlap;

        final subN = remaining > dayN ? dayN : remaining;
        dayN -= subN;
        remaining -= subN;

        final sub50 = remaining > day50 ? day50 : remaining;
        day50 -= sub50;
        remaining -= sub50;

        final sub100 = remaining > day100 ? day100 : remaining;
        day100 -= sub100;
        remaining -= sub100;

        final sub60 = remaining > day60 ? day60 : remaining;
        day60 -= sub60;
        remaining -= sub60;

        lunchApplied += (lunchOverlap - remaining);
      }
    }

    totalN += dayN;
    total50 += day50;
    total60 += day60;
    total100 += day100;

    cursor = segEnd;
  }

  return WorktimeCalcResult(
    minutesNormais: totalN,
    minutes50: total50,
    minutes60: total60,
    minutes100: total100,
    lunchMinutesApplied: lunchApplied,
    holidays: holidayHits,
  );
}

int _overlapMinutes(DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) {
  final start = aStart.isAfter(bStart) ? aStart : bStart;
  final end = aEnd.isBefore(bEnd) ? aEnd : bEnd;
  final diff = end.difference(start).inMinutes;
  return diff > 0 ? diff : 0;
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String _toYmd(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '$y-$m-$dd';
}

bool _isYmd(String s) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s);

String _mmToHHmm(int minutes) {
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

/// Algoritmo de Páscoa (calendário gregoriano) – funciona para anos modernos.
DateTime _easterSunday(int year) {
  // Meeus/Jones/Butcher Gregorian algorithm
  final a = year % 19;
  final b = year ~/ 100;
  final c = year % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31; // 3=March, 4=April
  final day = ((h + l - 7 * m + 114) % 31) + 1;
  return DateTime(year, month, day);
}
