// Shared building blocks for the admin Interaction screens (groups, broadcasts, polls).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../config/app_colors.dart';
import '../../../services/admin_interaction_service.dart';
import '../../../utils/error_message_utils.dart';

String interactionDate(DateTime? d) => d == null ? '-' : DateFormat('d MMM yyyy').format(d);
String interactionDateTime(DateTime? d) => d == null ? '-' : DateFormat('d MMM yyyy, h:mm a').format(d);

void showInteractionError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(ErrorMessageUtils.toUserFriendlyMessage(e)),
    backgroundColor: AppColors.error,
  ));
}

void showInteractionSuccess(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: AppColors.success,
  ));
}

PreferredSizeWidget interactionAppBar(String title, {List<Widget>? actions}) => AppBar(
      title: Text(title),
      actions: actions,
    );

class InteractionCard extends StatelessWidget {
  const InteractionCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFECEEF1)),
          ),
          child: child,
        ),
      ),
      ),
    );
  }
}

/// Scrollable (so pull-to-refresh works) error view with a Retry button.
class InteractionErrorView extends StatelessWidget {
  const InteractionErrorView({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 40),
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: AppColors.errorBg, shape: BoxShape.circle),
            child: const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 30),
          ),
        ),
        const SizedBox(height: 16),
        Text(message,
            textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4)),
        const SizedBox(height: 8),
        Center(child: TextButton(onPressed: onRetry, child: const Text('Retry'))),
      ],
    );
  }
}

class InteractionEmptyView extends StatelessWidget {
  const InteractionEmptyView({super.key, required this.icon, required this.title, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 40),
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 30, color: AppColors.primaryText),
          ),
        ),
        const SizedBox(height: 16),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.45)),
        ],
      ],
    );
  }
}

class InteractionChip extends StatelessWidget {
  const InteractionChip(this.label, {super.key, this.fg = AppColors.textSecondary, this.bg = AppColors.inputFill});
  final String label;
  final Color fg;
  final Color bg;

  factory InteractionChip.status(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return InteractionChip(status, fg: AppColors.success, bg: AppColors.successBg);
      case 'completed':
        return InteractionChip(status, fg: AppColors.info, bg: AppColors.infoBg);
      case 'draft':
        return InteractionChip(status, fg: AppColors.warning, bg: AppColors.warningBg);
      default:
        return InteractionChip(status);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

class InteractionSectionLabel extends StatelessWidget {
  const InteractionSectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 16),
        child: Text(text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      );
}

/// Field decoration; fill, borders and focus colours come from the app-wide input theme.
InputDecoration interactionInput(String hint, {Widget? prefixIcon}) => InputDecoration(
      hintText: hint,
      prefixIcon: prefixIcon,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );

class InteractionAvatar extends StatelessWidget {
  const InteractionAvatar({super.key, required this.name, this.url = '', this.radius = 18});
  final String name;
  final String url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    final hasUrl = url.startsWith('http');
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary.withValues(alpha: 0.14),
      foregroundImage: hasUrl ? NetworkImage(url) : null,
      child: Text(initials.isEmpty ? '?' : initials,
          style: TextStyle(fontSize: radius * 0.7, fontWeight: FontWeight.w700, color: AppColors.primaryText)),
    );
  }
}

/// Searchable multi-select list of staff. The parent owns [selected].
class StaffMultiSelect extends StatefulWidget {
  const StaffMultiSelect({
    super.key,
    required this.staff,
    required this.selected,
    required this.onChanged,
    this.maxHeight = 320,
  });
  final List<InteractionStaff> staff;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final double maxHeight;

  @override
  State<StaffMultiSelect> createState() => _StaffMultiSelectState();
}

class _StaffMultiSelectState extends State<StaffMultiSelect> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final filtered = widget.staff
        .where((s) => q.isEmpty || s.name.toLowerCase().contains(q) || s.department.toLowerCase().contains(q))
        .toList();
    final allSelected = filtered.isNotEmpty && filtered.every((s) => widget.selected.contains(s.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: interactionInput('Search staff...', prefixIcon: const Icon(Icons.search_rounded, size: 20)),
          onChanged: (v) => setState(() => _q = v),
        ),
        if (filtered.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                final next = Set<String>.from(widget.selected);
                if (allSelected) {
                  next.removeAll(filtered.map((s) => s.id));
                } else {
                  next.addAll(filtered.map((s) => s.id));
                }
                widget.onChanged(next);
              },
              child: Text(allSelected ? 'Clear shown' : 'Select shown'),
            ),
          ),
        Container(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFECEEF1)),
          ),
          child: filtered.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No staff found', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final s = filtered[i];
                    final sel = widget.selected.contains(s.id);
                    return CheckboxListTile(
                      dense: true,
                      value: sel,
                      controlAffinity: ListTileControlAffinity.trailing,
                      secondary: InteractionAvatar(name: s.name, url: s.avatar, radius: 16),
                      title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
                      subtitle: Text('${s.department} · ${s.designation}',
                          style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                      onChanged: (v) {
                        final next = Set<String>.from(widget.selected);
                        if (v == true) {
                          next.add(s.id);
                        } else {
                          next.remove(s.id);
                        }
                        widget.onChanged(next);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Primary full-width submit button with a busy state.
class InteractionSubmitButton extends StatelessWidget {
  const InteractionSubmitButton({super.key, required this.label, required this.busy, required this.onPressed});
  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: busy ? null : onPressed,
        child: busy
            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
            : Text(label),
      ),
    );
  }
}
