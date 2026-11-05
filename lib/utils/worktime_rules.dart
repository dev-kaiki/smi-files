// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers

import 'package:flutter/material.dart';

class WorkTimeBreakdown {
  final double horasNormais;
  final double horas50;
  final double horas100;

  const WorkTimeBreakdown({
    required this.horasNormais,
    required this.horas50,
    required this.horas100,
  });

  double get horasTotais => horasNormais + horas50 + horas100;
}

class BrHolidayUtils {
  static bool isHoliday(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final easter = _easterSunday(date.year);

    final fixed = <DateTime>{
      DateTime(date.year, 1, 1),   // Confraternização Universal
      DateTime(date.year, 4, 21),  // Tiradentes
      DateTime(date.year, 5, 1),   // Dia do Trabalho
      DateTime(date.year, 9, 7),   // Independência
      DateTime(date.year, 10, 12), // Nossa Senhora Aparecida
      DateTime(date.year, 11, 2),  // Finados
      DateTime(date.year, 11, 15), // Proclamação da República
      DateTime(date.year, 11, 20), // Consciência Negra
      DateTime(date.year, 12, 25), // Natal
    };

    final movable = <DateTime>{
      easter.subtract(const Duration(days: 48)), // Carnaval segunda
      easter.subtract(const Duration(days: 47)), // Carnaval terça
      easter.subtract(const Duration(days: 2)),  // Sexta-feira Santa
      easter,                                    // Páscoa
      easter.add(const Duration(days: 60)),      // Corpus Christi
    };

    return fixed.contains(d) || movable.contains(d);
  }

  static DateTime _easterSunday(int year) {
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
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime(year, month, day);
  }
}

class WorkTimeRules {
  static WorkTimeBreakdown calculate({
    required DateTime data,
    required TimeOfDay inicio,
    required TimeOfDay fim,
  }) {
    final start = _minutes(inicio);
    var end = _minutes(fim);
    if (end <= start) {
      throw ArgumentError('Horário final deve ser maior que o inicial.');
    }

    final date = DateTime(data.year, data.month, data.day);
    final weekday = date.weekday;
    final holiday = BrHolidayUtils.isHoliday(date);

    if (holiday || weekday == DateTime.sunday) {
      return WorkTimeBreakdown(horasNormais: 0, horas50: 0, horas100: (end - start) / 60.0);
    }

    if (weekday == DateTime.saturday) {
      return WorkTimeBreakdown(horasNormais: 0, horas50: (end - start) / 60.0, horas100: 0);
    }

    const normalStart = 7 * 60;
    const normalEnd = 17 * 60;

    final normalMinutes = _overlap(start, end, normalStart, normalEnd);
    final totalMinutes = end - start;
    final extra50Minutes = totalMinutes - normalMinutes;

    return WorkTimeBreakdown(
      horasNormais: normalMinutes / 60.0,
      horas50: extra50Minutes / 60.0,
      horas100: 0,
    );
  }

  static int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  static int _overlap(int aStart, int aEnd, int bStart, int bEnd) {
    final start = aStart > bStart ? aStart : bStart;
    final end = aEnd < bEnd ? aEnd : bEnd;
    return end > start ? end - start : 0;
  }
}
