// Loans & salary advances - the shapes HRMSbackend's loan module returns
// (/api/staff/loans/* and /api/admin/loans/*, serializers in
// services/loans/staffLoan.service.ts). Every record carries `id`; dates are ISO strings.

double _num(dynamic v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);
int _int(dynamic v) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? 0);
String _str(dynamic v) => v?.toString() ?? '';
DateTime? _date(dynamic v) {
  final s = v?.toString() ?? '';
  return s.isEmpty ? null : DateTime.tryParse(s)?.toLocal();
}

List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) => v is List
    ? v.whereType<Map>().map((e) => f(Map<String, dynamic>.from(e))).toList()
    : <T>[];

/// One enabled loan type from the company policy, with this employee's own max amount.
class LoanTypePolicy {
  LoanTypePolicy.fromJson(Map<String, dynamic> j)
      : id = _str(j['id']),
        name = _str(j['name']),
        code = _str(j['code']),
        description = _str(j['description']),
        maxAmount = _num(j['maxAmount']),
        minServiceMonths = _int(j['minServiceMonths']),
        interestMethod = _str(j['interestMethod']).isEmpty ? 'None' : _str(j['interestMethod']),
        interestRate = _num(j['interestRate']),
        minTenure = _int(j['minTenure']) == 0 ? 1 : _int(j['minTenure']),
        maxTenure = _int(j['maxTenure']) == 0 ? 12 : _int(j['maxTenure']),
        tenureOptions = (j['tenureOptions'] is List)
            ? (j['tenureOptions'] as List).map(_int).where((n) => n > 0).toList()
            : <int>[],
        requiresDocuments = j['requiresDocuments'] == true,
        documentTypes = (j['documentTypes'] is List)
            ? (j['documentTypes'] as List).map(_str).where((s) => s.isNotEmpty).toList()
            : <String>[],
        allowForeclosure = j['allowForeclosure'] == true;

  final String id, name, code, description, interestMethod;
  final double maxAmount, interestRate;
  final int minServiceMonths, minTenure, maxTenure;
  final List<int> tenureOptions;
  final List<String> documentTypes;
  final bool requiresDocuments, allowForeclosure;

  /// Tenure choices shown to the employee: the configured options inside min..max
  /// (as the policy says they are shown), or every month in the range when none are set.
  List<int> get tenureChoices {
    final opts = tenureOptions.where((n) => n >= minTenure && n <= maxTenure).toList()..sort();
    if (opts.isNotEmpty) return opts;
    return [for (var n = minTenure; n <= maxTenure; n++) n];
  }
}

class SalaryAdvancePolicy {
  SalaryAdvancePolicy.fromJson(Map<String, dynamic> j)
      : enabled = j['enabled'] == true,
        maxPctOfNet = _num(j['maxPctOfNet']),
        maxAmountCap = _num(j['maxAmountCap']),
        defaultRecovery = _str(j['defaultRecovery']).isEmpty ? 'Next Salary' : _str(j['defaultRecovery']),
        allowSplitRecovery = j['allowSplitRecovery'] == true,
        maxSplitMonths = _int(j['maxSplitMonths']) == 0 ? 1 : _int(j['maxSplitMonths']),
        maxAdvancesPerYear = _int(j['maxAdvancesPerYear']),
        minServiceMonths = _int(j['minServiceMonths']),
        cutoffDay = _int(j['cutoffDay']);

  final bool enabled, allowSplitRecovery;
  final double maxPctOfNet, maxAmountCap;
  final String defaultRecovery;
  final int maxSplitMonths, maxAdvancesPerYear, minServiceMonths, cutoffDay;

  /// Recovery choices the policy allows ('Next Salary', '2 Months', '3 Months').
  List<String> get recoveryChoices => [
        'Next Salary',
        if (allowSplitRecovery && maxSplitMonths >= 2) '2 Months',
        if (allowSplitRecovery && maxSplitMonths >= 3) '3 Months',
      ];
}

class LoanEligibility {
  LoanEligibility.fromJson(Map<String, dynamic> j)
      : eligible = j['eligible'] == true,
        reasons = (j['reasons'] is List) ? (j['reasons'] as List).map(_str).toList() : <String>[],
        meetsMinSalary = j['meetsMinSalary'] == true,
        activeLoans = _int(j['activeLoans']),
        maxActiveLoans = _int(j['maxActiveLoans']),
        serviceMonths = _int(j['serviceMonths']),
        maxAdvanceAmount = _num(j['maxAdvanceAmount']),
        advancesUsedThisYear = _int(j['advancesUsedThisYear']),
        netSalary = j['netSalary'] is num ? (j['netSalary'] as num).toDouble() : null;

  final bool eligible, meetsMinSalary;
  final List<String> reasons;
  final int activeLoans, maxActiveLoans, serviceMonths, advancesUsedThisYear;
  final double maxAdvanceAmount;

  /// Null when the organisation keeps salary private.
  final double? netSalary;
}

/// GET /staff/loans/policy
class LoanPolicyView {
  LoanPolicyView.fromJson(Map<String, dynamic> j)
      : loanModuleEnabled = j['loanModuleEnabled'] == true,
        salaryAdvanceEnabled = j['salaryAdvanceEnabled'] == true,
        maxEmiToNetSalaryPct = _num(j['maxEmiToNetSalaryPct']),
        policyText = _str(j['policyText']),
        loanTypes = _list(j['loanTypes'], LoanTypePolicy.fromJson),
        salaryAdvance = SalaryAdvancePolicy.fromJson(
            j['salaryAdvance'] is Map ? Map<String, dynamic>.from(j['salaryAdvance']) : const {}),
        eligibility = LoanEligibility.fromJson(
            j['eligibility'] is Map ? Map<String, dynamic>.from(j['eligibility']) : const {});

  final bool loanModuleEnabled, salaryAdvanceEnabled;
  final double maxEmiToNetSalaryPct;
  final String policyText;
  final List<LoanTypePolicy> loanTypes;
  final SalaryAdvancePolicy salaryAdvance;
  final LoanEligibility eligibility;
}

class LoanEmployee {
  LoanEmployee.fromJson(Map<String, dynamic> j)
      : staffId = _str(j['staffId']),
        employeeId = _str(j['employeeId']),
        name = _str(j['name']),
        department = _str(j['department']),
        designation = _str(j['designation']),
        branch = _str(j['branch']),
        monthlyGross = _num(j['monthlyGross']),
        monthlyNet = _num(j['monthlyNet']);

  final String staffId, employeeId, name, department, designation, branch;
  final double monthlyGross, monthlyNet;
}

class LoanApproval {
  LoanApproval.fromJson(Map<String, dynamic> j)
      : level = _str(j['level']),
        approverName = _str(j['approverName']),
        decision = _str(j['decision']).isEmpty ? 'Pending' : _str(j['decision']),
        remarks = _str(j['remarks']),
        decidedAt = _date(j['decidedAt']),
        approvedAmount = j['approvedAmount'] is num ? (j['approvedAmount'] as num).toDouble() : null;

  final String level, approverName, decision, remarks;
  final DateTime? decidedAt;
  final double? approvedAmount;
}

class LoanDocument {
  LoanDocument.fromJson(Map<String, dynamic> j)
      : id = _str(j['id']),
        name = _str(j['name']),
        type = _str(j['type']),
        url = _str(j['url']),
        uploadedAt = _date(j['uploadedAt']);

  final String id, name, type, url;
  final DateTime? uploadedAt;
}

/// A loan / advance request (before it becomes a loan).
class LoanRequest {
  LoanRequest.fromJson(Map<String, dynamic> j)
      : id = _str(j['id']),
        requestNo = _str(j['requestNo']),
        loanId = _str(j['loanId']),
        loanStatus = _str(j['loanStatus']),
        disbursedOn = _date(j['disbursedOn']),
        category = _str(j['category']),
        loanType = _str(j['loanType']),
        employee = LoanEmployee.fromJson(j['employee'] is Map ? Map<String, dynamic>.from(j['employee']) : const {}),
        requestedAmount = _num(j['requestedAmount']),
        purpose = _str(j['purpose']),
        reason = _str(j['reason']),
        preferredTenure = _int(j['preferredTenure']),
        advanceRecovery = _str(j['advanceRecovery']),
        appliedOn = _date(j['appliedOn']),
        requiredBy = _date(j['requiredBy']),
        status = _str(j['status']),
        documents = _list(j['documents'], LoanDocument.fromJson),
        approvals = _list(j['approvals'], LoanApproval.fromJson),
        currentLevel = _str(j['currentLevel']);

  final String id, requestNo, loanId, loanStatus, category, loanType, purpose, reason, advanceRecovery, status, currentLevel;
  final DateTime? disbursedOn, appliedOn, requiredBy;
  final LoanEmployee employee;
  final double requestedAmount;
  final int preferredTenure;
  final List<LoanDocument> documents;
  final List<LoanApproval> approvals;

  bool get isAdvance => category == 'SalaryAdvance';

  /// Statuses the employee may still cancel (backend: cancel is refused otherwise).
  bool get canCancel => const ['Pending', 'Manager Approved', 'HR Approved', 'Need Clarification'].contains(status);

  bool get needsClarification => status == 'Need Clarification';

  /// The approver's question when clarification was asked.
  String get clarificationQuestion {
    for (final a in approvals.reversed) {
      if (a.decision == 'Clarification' && a.remarks.isNotEmpty) return a.remarks;
    }
    return '';
  }

  bool get isOpen => const ['Pending', 'Manager Approved', 'HR Approved', 'Finance Approved', 'Need Clarification']
      .contains(status);
}

class EmiInstallment {
  EmiInstallment.fromJson(Map<String, dynamic> j)
      : no = _int(j['no']),
        dueDate = _date(j['dueDate']),
        opening = _num(j['opening']),
        principal = _num(j['principal']),
        interest = _num(j['interest']),
        total = _num(j['total']),
        paid = _num(j['paid']),
        closing = _num(j['closing']),
        status = _str(j['status']),
        paidOn = _date(j['paidOn']),
        note = _str(j['note']);

  EmiInstallment.preview({
    required this.no,
    required this.dueDate,
    required this.opening,
    required this.principal,
    required this.interest,
    required this.total,
    required this.closing,
  })  : paid = 0,
        status = 'Upcoming',
        paidOn = null,
        note = '';

  final int no;
  final DateTime? dueDate, paidOn;
  final double opening, principal, interest, total, paid, closing;
  final String status, note;
}

class LedgerEntry {
  LedgerEntry.fromJson(Map<String, dynamic> j)
      : id = _str(j['id']),
        date = _date(j['date']),
        description = _str(j['description']),
        reference = _str(j['reference']),
        debit = _num(j['debit']),
        credit = _num(j['credit']),
        balance = _num(j['balance']),
        mode = _str(j['mode']);

  final String id, description, reference, mode;
  final DateTime? date;
  final double debit, credit, balance;
}

class LoanActivity {
  LoanActivity.fromJson(Map<String, dynamic> j)
      : at = _date(j['at']),
        actor = _str(j['actor']),
        action = _str(j['action']),
        detail = _str(j['detail']);

  final DateTime? at;
  final String actor, action, detail;
}

/// An approved loan / advance with its schedule and ledger.
class Loan {
  Loan.fromJson(Map<String, dynamic> j)
      : id = _str(j['id']),
        loanNo = _str(j['loanNo']),
        category = _str(j['category']),
        loanType = _str(j['loanType']),
        employee = LoanEmployee.fromJson(j['employee'] is Map ? Map<String, dynamic>.from(j['employee']) : const {}),
        principal = _num(j['principal']),
        interestRate = _num(j['interestRate']),
        interestMethod = _str(j['interestMethod']),
        tenure = _int(j['tenure']),
        recoveryMode = _str(j['recoveryMode']),
        emiAmount = _num(j['emiAmount']),
        totalInterest = _num(j['totalInterest']),
        totalPayable = _num(j['totalPayable']),
        recovered = _num(j['recovered']),
        outstanding = _num(j['outstanding']),
        paidEmis = _int(j['paidEmis']),
        disbursedOn = _date(j['disbursedOn']),
        disbursementMode = _str(j['disbursementMode']),
        disbursementRef = _str(j['disbursementRef']),
        recoveryStart = _date(j['recoveryStart']),
        recoveryEnd = _date(j['recoveryEnd']),
        nextDueDate = _date(j['nextDueDate']),
        status = _str(j['status']),
        overdueAmount = _num(j['overdueAmount']),
        purpose = _str(j['purpose']),
        requestId = _str(j['requestId']),
        schedule = _list(j['schedule'], EmiInstallment.fromJson),
        ledger = _list(j['ledger'], LedgerEntry.fromJson),
        approvals = _list(j['approvals'], LoanApproval.fromJson),
        documents = _list(j['documents'], LoanDocument.fromJson),
        activity = _list(j['activity'], LoanActivity.fromJson);

  final String id, loanNo, category, loanType, interestMethod, recoveryMode, disbursementMode, disbursementRef, status, purpose, requestId;
  final LoanEmployee employee;
  final double principal, interestRate, emiAmount, totalInterest, totalPayable, recovered, outstanding, overdueAmount;
  final int tenure, paidEmis;
  final DateTime? disbursedOn, recoveryStart, recoveryEnd, nextDueDate;
  final List<EmiInstallment> schedule;
  final List<LedgerEntry> ledger;
  final List<LoanApproval> approvals;
  final List<LoanDocument> documents;
  final List<LoanActivity> activity;

  bool get isAdvance => category == 'SalaryAdvance';

  /// Live = still being repaid or about to be (backend LIVE_LOAN_STATUSES).
  bool get isLive => const ['Approved', 'Disbursed', 'Active', 'Defaulted'].contains(status);
}
