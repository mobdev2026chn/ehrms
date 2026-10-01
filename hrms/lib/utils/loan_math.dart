// EMI maths for loans - an exact port of HRMSbackend services/loans/loanMath.ts
// (itself a port of the web's shared/loans/loanMath.ts), rounding included, so the
// estimated EMI shown before applying is the figure the employee is actually charged.
// Change one, change the others.

import 'dart:math' as math;

import '../models/loan_models.dart';

class EmiQuote {
  const EmiQuote(this.emi, this.totalInterest, this.totalPayable, this.schedule);
  final double emi, totalInterest, totalPayable;
  final List<EmiInstallment> schedule;
}

/// Calendar month-end `offset` months after [start] (UTC date, like the backend).
DateTime _monthEnd(DateTime start, int offset) =>
    DateTime.utc(start.year, start.month + offset + 1, 0);

/// First day of next month - the earliest a new loan's recovery can start.
DateTime nextMonthStart([DateTime? from]) {
  final f = (from ?? DateTime.now()).toUtc();
  return DateTime.utc(f.year, f.month + 1, 1);
}

/// JS Math.round (half up, incl. negatives) - Dart's round() rounds half away from zero.
int _round(num x) => (x + 0.5).floor();

/// Builds a repayment schedule: None = principal split evenly; Flat = interest on the
/// full principal for the whole tenure, split evenly; Reducing = amortised EMI.
EmiQuote buildSchedule(double principal, double annualRatePct, int tenure, String method, {DateTime? recoveryStart}) {
  final start = recoveryStart ?? nextMonthStart();
  final p = principal.isFinite ? _round(principal).clamp(0, 1 << 52).toInt() : 0;
  final n = tenure < 1 ? 1 : tenure;
  final rate = method == 'None' ? 0.0 : (annualRatePct.isFinite && annualRatePct > 0 ? annualRatePct : 0.0);
  final schedule = <EmiInstallment>[];
  if (p == 0) return EmiQuote(0, 0, 0, schedule);

  EmiInstallment row(int i, int opening, int principalPart, int interest, int closing) => EmiInstallment.preview(
        no: i + 1,
        dueDate: _monthEnd(start, i),
        opening: opening.toDouble(),
        principal: principalPart.toDouble(),
        interest: interest.toDouble(),
        total: (principalPart + interest).toDouble(),
        closing: closing.toDouble(),
      );

  if (method == 'Reducing' && rate > 0) {
    final r = rate / 12 / 100;
    // Same libm pow as JS Math.pow, so a .5 rounding boundary lands the same way.
    final pow = math.pow(1 + r, n).toDouble();
    final emi = _round(p * r * pow / (pow - 1));
    var balance = p;
    var totalInterest = 0;
    for (var i = 0; i < n; i++) {
      final interest = _round(balance * r);
      final principalPart = i == n - 1 ? balance : emi - interest;
      final closing = (balance - principalPart) < 0 ? 0 : balance - principalPart;
      schedule.add(row(i, balance, principalPart, interest, closing));
      totalInterest += interest;
      balance = closing;
    }
    return EmiQuote(emi.toDouble(), totalInterest.toDouble(), (p + totalInterest).toDouble(), schedule);
  }

  final totalInterest = rate > 0 ? _round(p * rate * n / 12 / 100) : 0;
  int evenSplit(int total) {
    final up = (total / n).ceil();
    return up * (n - 1) <= total ? up : (total / n).floor();
  }

  final principalPer = evenSplit(p);
  final interestPer = evenSplit(totalInterest);
  var balance = p;
  var interestLeft = totalInterest;
  for (var i = 0; i < n; i++) {
    final last = i == n - 1;
    final principalPart = last ? balance : principalPer;
    final interest = last ? interestLeft : interestPer;
    final closing = balance - principalPart;
    schedule.add(row(i, balance, principalPart, interest, closing));
    balance = closing;
    interestLeft -= interest;
  }
  return EmiQuote((principalPer + interestPer).toDouble(), totalInterest.toDouble(), (p + totalInterest).toDouble(), schedule);
}

/// Months a salary advance is recovered over.
int advanceRecoveryMonths(String recovery) => switch (recovery) {
      '2 Months' => 2,
      '3 Months' => 3,
      _ => 1,
    };

/// A salary advance split evenly over its recovery months (no interest), as the backend does.
List<int> advanceInstallments(int amount, int months) {
  final n = months < 1 ? 1 : months;
  final per = amount ~/ n;
  return [for (var i = 0; i < n; i++) i == n - 1 ? amount - per * (n - 1) : per];
}
