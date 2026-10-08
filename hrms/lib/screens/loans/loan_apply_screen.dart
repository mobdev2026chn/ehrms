// Request a Loan (web /staff/loans/apply) and Salary Advance (web
// /staff/loans/salary-advance) - POST /staff/loans/requests, laid out like the web forms.
// The backend leaves the amount cap, tenure range, service period, advances-per-year
// and EMI-to-net checks to the form, so they are checked here before submitting.

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../models/loan_models.dart';
import '../../services/loan_service.dart';
import '../../utils/error_message_utils.dart';
import '../../utils/loan_math.dart';
import '../../utils/snackbar_utils.dart';
import '../../widgets/app_card.dart';
import 'loan_widgets.dart';

class LoanApplyScreen extends StatefulWidget {
  const LoanApplyScreen({super.key, required this.policy, required this.category});
  final LoanPolicyView policy;
  final String category; // 'Loan' | 'SalaryAdvance'

  @override
  State<LoanApplyScreen> createState() => _LoanApplyScreenState();
}

class _PickedDoc {
  _PickedDoc(this.name, this.dataUrl, this.type);
  final String name, dataUrl;
  String type; // document label (policy documentTypes)
}

class _LoanApplyScreenState extends State<LoanApplyScreen> {
  /// The web form's purposes (HRMSbackend loanRequestModel: "one of the configured
  /// purposes - Emergency, Medical, Education, Marriage, House Rent, Others").
  static const _purposes = ['Emergency', 'Medical', 'Education', 'Marriage', 'House Rent', 'Others'];
  static const _maxDocs = 6;
  static const _maxDocBytes = 5 * 1024 * 1024;
  static const _mimeByExt = {
    'pdf': 'application/pdf',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'webp': 'image/webp',
  };

  final _amount = TextEditingController();
  final _reason = TextEditingController();
  LoanTypePolicy? _type;
  String? _purpose;
  int? _tenure;
  String _recovery = 'Next Salary';
  DateTime? _requestedDate;
  bool _agreed = false;
  bool _submitting = false;
  final List<_PickedDoc> _docs = [];

  bool get _isAdvance => widget.category == 'SalaryAdvance';
  LoanPolicyView get _p => widget.policy;

  @override
  void initState() {
    super.initState();
    if (_isAdvance) {
      final choices = _p.salaryAdvance.recoveryChoices;
      _recovery = choices.contains(_p.salaryAdvance.defaultRecovery) ? _p.salaryAdvance.defaultRecovery : choices.first;
    }
    _amount.addListener(() => setState(() {}));
    _reason.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  double get _amountValue => double.tryParse(_amount.text.replaceAll(',', '').trim()) ?? 0;
  double get _maxAmount => _isAdvance ? _p.eligibility.maxAdvanceAmount : (_type?.maxAmount ?? 0);

  EmiQuote? _quoteFor(int months) {
    final t = _type;
    if (t == null || _amountValue <= 0) return null;
    return buildSchedule(_amountValue, t.interestRate, months, t.interestMethod);
  }

  /// Everything the web form checks; the first problem, or null when it can submit.
  String? _problem() {
    final amount = _amountValue;
    final e = _p.eligibility;
    if (!_isAdvance && _type == null) return 'Select the loan type.';
    if (amount <= 0) return 'Enter the amount.';
    if (_maxAmount > 0 && amount > _maxAmount) return 'The maximum you can request is ${loanMoney(_maxAmount)}.';
    if (_isAdvance) {
      final sa = _p.salaryAdvance;
      if (sa.minServiceMonths > 0 && e.serviceMonths < sa.minServiceMonths) {
        return 'Salary advances need ${sa.minServiceMonths} months of service (you have ${e.serviceMonths}).';
      }
      if (sa.maxAdvancesPerYear > 0 && e.advancesUsedThisYear >= sa.maxAdvancesPerYear) {
        return 'You have used all ${sa.maxAdvancesPerYear} salary advances allowed in a year.';
      }
      if (_reason.text.trim().isEmpty) return 'Enter the reason.';
      return null;
    }
    final t = _type!;
    if (t.minServiceMonths > 0 && e.serviceMonths < t.minServiceMonths) {
      return '${t.name} needs ${t.minServiceMonths} months of service (you have ${e.serviceMonths}).';
    }
    if (_purpose == null) return 'Select the purpose.';
    if (_reason.text.trim().isEmpty) return 'Enter the reason.';
    if (_tenure == null) return 'Choose the preferred EMI.';
    final q = _quoteFor(_tenure!);
    final net = e.netSalary;
    if (q != null && net != null && net > 0 && _p.maxEmiToNetSalaryPct > 0 && q.emi > net * _p.maxEmiToNetSalaryPct / 100) {
      return 'The EMI (${loanMoney(q.emi)}) is more than ${_p.maxEmiToNetSalaryPct.toStringAsFixed(0)}% of your net salary. '
          'Choose a smaller amount or a longer tenure.';
    }
    if (_requestedDate == null) return 'Choose the requested date.';
    if (t.requiresDocuments && _docs.isEmpty) return 'Attach the supporting documents for ${t.name}.';
    if (!_agreed) return 'Please agree to the company policy.';
    return null;
  }

  Future<void> _pickDocs() async {
    if (_docs.length >= _maxDocs) {
      SnackBarUtils.showSnackBar(context, 'You can attach up to $_maxDocs files.', isError: true);
      return;
    }
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: _mimeByExt.keys.toList(),
    );
    if (res == null || !mounted) return;
    final labels = _type?.documentTypes ?? const <String>[];
    for (final f in res.files) {
      if (_docs.length >= _maxDocs) break;
      final bytes = f.bytes;
      final mime = _mimeByExt[(f.extension ?? '').toLowerCase()];
      if (bytes == null || mime == null) continue;
      if (bytes.length > _maxDocBytes) {
        SnackBarUtils.showSnackBar(context, '${f.name} is larger than 5 MB.', isError: true);
        continue;
      }
      _docs.add(_PickedDoc(f.name, 'data:$mime;base64,${base64Encode(bytes)}', labels.isNotEmpty ? labels.first : 'Document'));
    }
    setState(() {});
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _requestedDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _requestedDate = picked);
  }

  Future<void> _submit() async {
    final problem = _problem();
    if (problem != null) {
      SnackBarUtils.showSnackBar(context, problem, isError: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      final req = await LoanService().submitRequest(
        category: widget.category,
        amount: _amountValue,
        reason: _reason.text.trim(),
        loanType: _isAdvance ? null : _type!.id,
        purpose: _isAdvance ? null : _purpose,
        preferredTenure: _isAdvance ? null : _tenure,
        advanceRecovery: _isAdvance ? _recovery : null,
        requiredBy: _isAdvance ? null : _requestedDate,
        documents: [for (final d in _docs) {'name': d.name, 'type': d.type, 'data': d.dataUrl}],
      );
      if (!mounted) return;
      SnackBarUtils.showSnackBar(context, 'Request ${req.requestNo} submitted for approval.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      SnackBarUtils.showSnackBar(context, ErrorMessageUtils.toUserFriendlyMessage(e), isError: true);
    }
  }

  // ── Layout helpers ──

  Widget _label(String text, {bool required = true}) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: text, style: AppTextStyles.label.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600)),
          if (required) const TextSpan(text: ' *', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
        ])),
      );

  // Fill, borders and focus colours come from the app InputDecorationTheme.
  InputDecoration _input({String? hint, Widget? prefix, String? helper}) => InputDecoration(
        hintText: hint,
        helperText: helper,
        helperMaxLines: 2,
        prefixIcon: prefix,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      );

  /// White card with a header line, like the web form sections.
  Widget _section(String title, List<Widget> children) => AppCard(
        margin: const EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.zero,
        border: Border.all(color: kLoanHairline),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: kLoanHairline)),
              ),
              child: Row(children: [
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: AppTextStyles.headingSmall)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ],
        ),
      );

  Widget _amountField() => TextField(
        controller: _amount,
        keyboardType: TextInputType.number,
        decoration: _input(
          hint: '0',
          prefix: const Padding(
            padding: EdgeInsets.only(left: 14, right: 6),
            child: Text('₹', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          ),
          helper: _maxAmount > 0 ? 'Maximum ${loanMoney(_maxAmount)}' : null,
        ).copyWith(prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0)),
      );

  Widget _reasonField() => TextField(controller: _reason, minLines: 4, maxLines: 6, decoration: _input());

  @override
  Widget build(BuildContext context) {
    final problem = _problem();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_isAdvance ? 'Salary Advance' : 'Request Loan'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        children: [
          if (_isAdvance) ..._advanceForm() else ..._loanForm(),
          if (problem != null && (_amountValue > 0 || _reason.text.isNotEmpty))
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: AppColors.errorBg, borderRadius: BorderRadius.circular(12)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(problem, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
                  ),
                ],
              ),
            ),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: Opacity(
              opacity: problem == null ? 1 : 0.5,
              child: ElevatedButton.icon(
                onPressed: _submitting || problem != null ? null : _submit,
                icon: _submitting
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(_isAdvance ? 'Submit' : 'Submit Request'),
                // Keep the disabled state looking like a faded primary button (the Opacity above).
                style: ElevatedButton.styleFrom(
                  disabledBackgroundColor: AppColors.primary,
                  disabledForegroundColor: AppColors.onPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  List<Widget> _loanForm() {
    final t = _type;
    return [
      _section('Loan Details', [
        _label('Loan Type'),
        DropdownButtonFormField<String>(
          initialValue: t?.id,
          isExpanded: true,
          hint: const Text('Select loan type'),
          decoration: _input(),
          items: [for (final lt in _p.loanTypes) DropdownMenuItem(value: lt.id, child: Text(lt.name, overflow: TextOverflow.ellipsis))],
          onChanged: (id) => setState(() {
            _type = _p.loanTypes.firstWhere((x) => x.id == id);
            final choices = _type!.tenureChoices;
            _tenure = choices.contains(_tenure) ? _tenure : null;
          }),
        ),
        if (t != null && t.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(t.description, style: AppTextStyles.bodySmall.copyWith(fontSize: 12)),
          ),
        _label('Loan Amount'),
        _amountField(),
        _label('Purpose'),
        DropdownButtonFormField<String>(
          initialValue: _purpose,
          isExpanded: true,
          hint: const Text('Select purpose'),
          decoration: _input(),
          items: [for (final p in _purposes) DropdownMenuItem(value: p, child: Text(p))],
          onChanged: (v) => setState(() => _purpose = v),
        ),
        _label('Reason'),
        _reasonField(),
        _label('Preferred EMI'),
        if (t == null)
          const Text('Select a loan type first.', style: AppTextStyles.bodySmall)
        else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final n in t.tenureChoices) _emiOption(n)],
          ),
          const SizedBox(height: 8),
          Text(
            t.interestMethod == 'None' || t.interestRate == 0
                ? 'No interest'
                : 'Interest ${t.interestRate.toStringAsFixed(t.interestRate % 1 == 0 ? 0 : 2)}% p.a. (${t.interestMethod}). The approver may change the final terms.',
            style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
          ),
        ],
        _label('Requested Date'),
        InkWell(
          onTap: _pickDate,
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: _input().copyWith(suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20)),
            child: Text(
              _requestedDate == null ? 'dd/mm/yyyy' : loanDate(_requestedDate),
              style: TextStyle(color: _requestedDate == null ? AppColors.textCaption : AppColors.textPrimary),
            ),
          ),
        ),
        if (t != null && (t.requiresDocuments || t.documentTypes.isNotEmpty)) ..._documents(t),
      ]),
      _agreementCard(),
    ];
  }

  /// One Preferred EMI choice: the tenure and the EMI it gives for the entered amount.
  Widget _emiOption(int months) {
    final selected = _tenure == months;
    final q = _quoteFor(months);
    return InkWell(
      onTap: () => setState(() => _tenure = months),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 104,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.12) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.primary : kLoanHairline, width: selected ? 1.6 : 1),
        ),
        child: Column(
          children: [
            Text('$months months', style: AppTextStyles.label.copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(q == null ? '—' : '${loanMoney(q.emi)}/mo',
                style: AppTextStyles.caption.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? AppColors.primaryText : AppColors.textSecondary,
                )),
          ],
        ),
      ),
    );
  }

  List<Widget> _documents(LoanTypePolicy t) => [
        _label('Supporting Documents', required: t.requiresDocuments),
        if (t.documentTypes.isNotEmpty)
          Text('Needed: ${t.documentTypes.join(', ')}', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
        Text('PDF or image, up to 6 files of 5 MB each.', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        for (final d in _docs)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kLoanHairline),
            ),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.description_outlined, size: 20, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.name,
                      overflow: TextOverflow.ellipsis, style: AppTextStyles.label.copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
                  if (t.documentTypes.length > 1)
                    DropdownButton<String>(
                      value: t.documentTypes.contains(d.type) ? d.type : t.documentTypes.first,
                      isDense: true,
                      underline: const SizedBox.shrink(),
                      style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.primaryText),
                      items: [for (final l in t.documentTypes) DropdownMenuItem(value: l, child: Text(l))],
                      onChanged: (v) => setState(() => d.type = v ?? d.type),
                    ),
                ]),
              ),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
                onPressed: () => setState(() => _docs.remove(d)),
              ),
            ]),
          ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: _pickDocs,
          icon: const Icon(Icons.attach_file_rounded, size: 18),
          label: const Text('Attach files'),
        ),
      ];

  Widget _agreementCard() => AppCard(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        border: Border.all(color: kLoanHairline),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              value: _agreed,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text.rich(TextSpan(children: [
                TextSpan(text: 'I agree with company policy', style: AppTextStyles.label.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600)),
                const TextSpan(text: ' *', style: TextStyle(color: AppColors.error)),
              ])),
              onChanged: (v) => setState(() => _agreed = v ?? false),
            ),
            if (_p.policyText.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 6),
                child: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Company loan policy'),
                      content: SingleChildScrollView(child: Text(_p.policyText)),
                      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
                    ),
                  ),
                  child: const Text('Read the policy'),
                ),
              ),
          ],
        ),
      );

  List<Widget> _advanceForm() {
    final sa = _p.salaryAdvance;
    final months = advanceRecoveryMonths(_recovery);
    final parts = _amountValue > 0 ? advanceInstallments(_amountValue.round(), months) : <int>[];
    final afterCutoff = sa.cutoffDay > 0 && DateTime.now().day > sa.cutoffDay;
    Widget box(String label, String value, {Color? color}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.sectionLabel.copyWith(letterSpacing: 0.6, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: AppTextStyles.headingMedium.copyWith(
                        fontSize: 20, fontWeight: FontWeight.w700, color: color ?? AppColors.textPrimary)),
              ),
            ]),
          ),
        );
    return [
      LoanCard(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          box('ELIGIBLE AMOUNT', loanMoney(_p.eligibility.maxAdvanceAmount), color: AppColors.primaryText),
          const SizedBox(width: 12),
          box('MAXIMUM', '${sa.maxPctOfNet.toStringAsFixed(sa.maxPctOfNet % 1 == 0 ? 0 : 1)}% Salary'),
        ]),
      ),
      const SizedBox(height: 12),
      _section('Request', [
        _label('Requested Amount'),
        _amountField(),
        _label('Recovery'),
        DropdownButtonFormField<String>(
          initialValue: _recovery,
          isExpanded: true,
          decoration: _input(),
          items: [for (final c in sa.recoveryChoices) DropdownMenuItem(value: c, child: Text(c))],
          onChanged: (v) => setState(() => _recovery = v ?? _recovery),
        ),
        if (parts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Deducted from salary: ${parts.map(loanMoney).join(' + ')} (no interest)',
                style: AppTextStyles.bodySmall.copyWith(fontSize: 12)),
          ),
        if (afterCutoff)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: AppColors.infoBg, borderRadius: BorderRadius.circular(10)),
            child: Text("Requests after the ${sa.cutoffDay}th are recovered from the following month's payroll.",
                style: AppTextStyles.bodySmall.copyWith(fontSize: 12, color: AppColors.info)),
          ),
        _label('Reason'),
        _reasonField(),
      ]),
    ];
  }
}
