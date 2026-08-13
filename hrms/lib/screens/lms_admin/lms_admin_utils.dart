// hrms/lib/screens/lms_admin/lms_admin_utils.dart
// Shared parsing helpers + small reusable form widgets for the admin LMS
// screens. Keeps the per-screen files focused on layout/logic.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';

class LmsAdminUtils {
  LmsAdminUtils._();

  /// Normalises a service `data` payload (List, or Map keyed by one of [keys])
  /// into a `List<Map<String, dynamic>>`.
  static List<Map<String, dynamic>> asMapList(dynamic data, List<String> keys) {
    List<dynamic> raw;
    if (data is List) {
      raw = data;
    } else if (data is Map) {
      raw = const [];
      for (final k in keys) {
        if (data[k] is List) {
          raw = data[k] as List;
          break;
        }
      }
    } else {
      raw = const [];
    }
    return raw
        .whereType<dynamic>()
        .map((e) => e is Map<String, dynamic>
            ? e
            : (e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{}))
        .where((m) => m.isNotEmpty)
        .toList();
  }

  /// Extracts category display names from a categories payload.
  static List<String> categoryNames(dynamic data) {
    List<dynamic> raw;
    if (data is List) {
      raw = data;
    } else if (data is Map && data['categories'] is List) {
      raw = data['categories'] as List;
    } else {
      raw = const [];
    }
    return raw
        .map((e) =>
            e is String ? e : (e is Map ? (e['name'] ?? e['title'] ?? '') : '')
                .toString())
        .where((s) => s.toString().isNotEmpty)
        .map((s) => s.toString())
        .toSet()
        .toList();
  }

  static int toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is List) return v.length;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  static String fmtDate(dynamic v, {String pattern = 'dd MMM yyyy'}) {
    final d = DateTime.tryParse(v?.toString() ?? '');
    return d == null ? '—' : DateFormat(pattern).format(d.toLocal());
  }

  // ── Reusable widgets ──────────────────────────────────────────────────────
  static Widget searchField({
    required String hint,
    required ValueChanged<String> onChanged,
    TextEditingController? controller,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textCaption, fontSize: 14),
        prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textCaption),
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.primary, width: 1.4),
        ),
      ),
    );
  }

  static Widget dropdown({
    required String hint,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          isExpanded: true,
          isDense: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
          hint: Text(hint,
              style: const TextStyle(fontSize: 13, color: AppColors.textCaption)),
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(hint, style: const TextStyle(fontSize: 13)),
            ),
            ...items.map(
              (e) => DropdownMenuItem<String?>(
                value: e,
                child: Text(e, style: const TextStyle(fontSize: 13)),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  static Widget emptyState(String message, {IconData icon = Icons.inbox_outlined}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          children: [
            Icon(icon, size: 48, color: AppColors.textHint),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  /// Status pill — colour resolved from common LMS statuses.
  static Widget statusPill(String status) {
    final s = status.toLowerCase();
    Color fg;
    if (s.contains('live')) {
      fg = AppColors.success;
    } else if (s.contains('progress')) {
      fg = AppColors.warning;
    } else if (s.contains('complete') || s.contains('ended') || s.contains('approved')) {
      fg = AppColors.info;
    } else if (s.contains('reject') || s.contains('cancel')) {
      fg = AppColors.error;
    } else {
      fg = AppColors.textSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.isEmpty ? '—' : status,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
