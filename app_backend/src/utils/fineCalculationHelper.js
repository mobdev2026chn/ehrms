/**
 * Fine calculation for attendance (check-in/check-out).
 * Uses only company.settings.payroll.fineCalculation (settings.payroll).
 * Formula (shiftBased): Fine = (Daily Salary ÷ Shift Hours) × (Late/Early Minutes ÷ 60)
 * When fineRules exist, applies matching rule by applyTo ('lateArrival' | 'earlyExit' | 'both').
 */

const { getCalendarDaysInMonth, calculateDaysExcludingWeeklyOffsOnly } = require('./salaryCalendarDays.util');

/**
 * Per-day salary denominator for fines, configured per company (businesses table)
 * at `settings.payroll.fineCalculation.daysBasis`. Implements the formula:
 *   Per Day Salary = Monthly (gross) Salary ÷ (number of days by this basis)
 *   Fine = (Per Day Salary ÷ Working Hours) × (Fine minutes ÷ 60)
 *
 * Basis:
 *   - 'calendarDays'    → calendar length of month (28–31)
 *   - 'fixedDays'       → `fixedDays` value (e.g. 30); falls back to excludeWeekOffs when unset
 *   - 'excludeWeekOffs' → month days minus weekly offs only (DEFAULT for every business,
 *                          including legacy docs where the field is absent)
 *
 * @param {Object} params
 * @param {Object} params.company - Company doc (reads settings.payroll.fineCalculation + business week-off)
 * @param {number} params.year
 * @param {number} params.month1 - 1–12
 * @param {string} [params.weeklyOffPattern]
 * @param {Array<{day:number}>} [params.weeklyHolidays]
 * @returns {number} day count (>= 1)
 */
function resolveFineDenominatorDays({ company, year, month1, weeklyOffPattern, weeklyHolidays }) {
    const m0 = Number(month1) - 1;
    const fc = company?.settings?.payroll?.fineCalculation || {};
    const basis = String(fc.daysBasis || 'excludeWeekOffs').trim().toLowerCase().replace(/[_\s]/g, '');
    const excludeWeekOffs = () => Math.max(1, calculateDaysExcludingWeeklyOffsOnly(
        year,
        m0,
        weeklyOffPattern === 'oddEvenSaturday' ? 'oddEvenSaturday' : 'standard',
        null,
        Array.isArray(weeklyHolidays) ? weeklyHolidays : null,
    ));
    if (basis === 'calendardays' || basis === 'calendar') {
        return Math.max(1, getCalendarDaysInMonth(year, m0));
    }
    if (basis === 'fixeddays' || basis === 'fixed') {
        const fixed = Number(fc.fixedDays) || 0;
        return fixed > 0 ? Math.max(1, Math.floor(fixed)) : excludeWeekOffs();
    }
    return excludeWeekOffs();
}

/**
 * Get effective fine config from company. Only reads settings.payroll.fineCalculation.
 * @param {Object} company - Company document
 * @returns {Object} { enabled, graceTimeMinutes, calculationType, finePerHour, fineRules }
 */
function getEffectiveFineConfig(company) {
    const source = company?.settings?.payroll?.fineCalculation;
    if (!source) {
        const hasCompany = !!company;
        const hasPayroll = !!(company?.settings?.payroll);
        console.log('[Fine] getEffectiveFineConfig: no payroll.fineCalculation (company=', hasCompany, 'settings.payroll=', hasPayroll, ') => using disabled config. Ensure Company schema has settings.payroll.fineCalculation and DB document has it with enabled: true.');
        return { enabled: false, graceTimeMinutes: 0, fineRules: [], fromPayroll: false };
    }
    const enabled = source.enabled === true && (source.applyFines !== false);
    console.log('[Fine] getEffectiveFineConfig: payroll.fineCalculation found, enabled=', enabled, 'calculationMethod=', source.calculationMethod || source.calculationType);
    // Backend fallback supports only:
    // - 'shiftBased'
    // - 'fixedPerHour'
    // If config contains other values (e.g. calculationMethod='custom'),
    // we still want default fine to behave like shiftBased when no fineRule matches.
    const rawCalcType = source.calculationType || source.calculationMethod || 'shiftBased';
    const calculationType = rawCalcType === 'fixedPerHour' ? 'fixedPerHour' : 'shiftBased';
    const fineRules = Array.isArray(source.fineRules) ? source.fineRules : [];
    const graceTimeMinutes = source.graceTimeMinutes ?? 0;
    const finePerHour = source.finePerHour ?? 0;
    return {
        enabled,
        graceTimeMinutes,
        calculationType,
        finePerHour,
        fineRules,
        fromPayroll: true
    };
}

/**
 * Calculate fine amount for late arrival or early exit using formula and optional fineRules.
 * Parity with web `backend/src/utils/fineCalculation.util.ts` (`calculateFineAmount`).
 *
 * @param {number} dailySalary - Daily **net** (used for fixedPerHour derivation & default base when gross omitted)
 * @param {number|null|undefined} dailyGrossForRules - Daily **gross** for 1x/2x/3x/halfDay/fullDay/custom rules &
 *   shiftBased default; when null/0, falls back to dailySalary (backward compatible)
 * @returns {number} Fine amount (>= 0)
 */
function calculateFineAmount(minutes, applyToType, fineConfig, dailySalary, shiftHours, dailyGrossForRules = null) {
    const logPrefix = '[Fine]';
    const testTag = '[Fine][formula][test]';
    if (minutes > 0) {
        console.log(logPrefix, 'calculateFineAmount', applyToType, 'minutes=', minutes, 'enabled=', !!fineConfig?.enabled, 'dailySalary=', dailySalary, 'shiftHours=', shiftHours);
    }
    if (!fineConfig || !fineConfig.enabled || minutes <= 0) {
        if (minutes > 0) {
            console.log(logPrefix, applyToType, 'SKIP => fineAmount=0 (enabled=', !!fineConfig?.enabled, 'minutes=', minutes, ')');
        }
        return 0;
    }

    const rules = fineConfig.fineRules || [];
    const applyToMatch = (applyTo) => !applyTo || applyTo === applyToType || applyTo === 'both';
    let matchingRule = rules.find((r) => applyToMatch(r.applyTo));
    // Open-shift "short hours" checkout uses earlyExit; many configs only define lateArrival.
    // If no early/both rule exists, reuse the late-arrival rule so under-worked minutes are fined the same way.
    let ruleFallbackFromLate = false;
    if (!matchingRule && applyToType === 'earlyExit' && rules.length > 0) {
        matchingRule = rules.find((r) => {
            const a = (r.applyTo || 'lateArrival').toString().toLowerCase();
            return a === 'latearrival' || a === 'both';
        });
        if (matchingRule) ruleFallbackFromLate = true;
    }

    let amount = 0;
    let formulaUsed = '';
    const grossBase =
        dailyGrossForRules != null && Number(dailyGrossForRules) > 0
            ? Number(dailyGrossForRules)
            : (dailySalary != null ? Number(dailySalary) : 0);

    if (matchingRule) {
        const hourlyRate = shiftHours > 0 && grossBase > 0 ? grossBase / shiftHours : 0;
        const hours = minutes / 60;
        amount = applyRuleAmount(matchingRule, minutes, grossBase, shiftHours);
        formulaUsed = `rule type=${matchingRule.type} applyTo=${matchingRule.applyTo || 'both'} | dailyGross=${grossBase} dailyNet=${dailySalary} shiftHours=${shiftHours} hourlyRate=${hourlyRate.toFixed(4)} minutes=${minutes} hours=${hours.toFixed(4)}`;
        const rt = String(matchingRule.type || '').toLowerCase();
        let ruleExpansion = '';
        if (rt === '1xsalary') {
            ruleExpansion = `1xSalary: (gross÷shiftHours)×(minutes÷60) = (${grossBase}÷${shiftHours})×(${minutes}÷60) = ${hourlyRate.toFixed(4)}×${hours.toFixed(4)} = ${(hourlyRate * hours).toFixed(4)}`;
        } else if (rt === '2xsalary') {
            ruleExpansion = `2xSalary: 2×(gross÷shiftHours)×(minutes÷60) = 2×${hourlyRate.toFixed(4)}×${hours.toFixed(4)} = ${(2 * hourlyRate * hours).toFixed(4)}`;
        } else if (rt === '3xsalary') {
            ruleExpansion = `3xSalary: 3×(gross÷shiftHours)×(minutes÷60) = 3×${hourlyRate.toFixed(4)}×${hours.toFixed(4)} = ${(3 * hourlyRate * hours).toFixed(4)}`;
        } else if (rt === 'halfday') {
            ruleExpansion = `halfDay: 0.5×hourlyRate×hours = 0.5×${hourlyRate.toFixed(4)}×${hours.toFixed(4)} = ${(hourlyRate * hours * 0.5).toFixed(4)}`;
        } else if (rt === 'fullday') {
            ruleExpansion = `fullDay: ${hours >= shiftHours ? 'gross' : 'gross×(hours/shiftHours)'} => ${Number(amount).toFixed(4)}`;
        } else if (rt === 'custom') {
            const ca = matchingRule.customAmount ?? 0;
            const unit = (matchingRule.customAmountUnit || 'perHour').toLowerCase();
            ruleExpansion = `custom: amount=${ca} unit=${unit} | applied result=${Number(amount).toFixed(4)}`;
        } else {
            ruleExpansion = `default: hourlyRate×hours = ${hourlyRate.toFixed(4)}×${hours.toFixed(4)} = ${(hourlyRate * hours).toFixed(4)}`;
        }
        console.log(testTag, applyToType, '| path=fineRule', ruleFallbackFromLate ? '(earlyExit fell back to late/both rule)' : '');
        console.log(testTag, applyToType, '|', ruleExpansion);
        console.log(testTag, applyToType, '| applyRuleAmount result (pre-round)=', Number(amount).toFixed(6));
    } else {
        // IMPORTANT business rule:
        // - If fineRules are provided and none match this action (lateArrival/earlyExit),
        //   DO NOT apply default formula for this action.
        // - Default formula fallback is used only when fineRules are empty.
        if (rules.length > 0) {
            formulaUsed = `rule-miss: fineRules exist but none match applyTo=${applyToType}; fineAmount=0`;
            const result = 0;
            console.log(testTag, applyToType, '| path=noMatchingRule |', formulaUsed);
            console.log(logPrefix, 'FORMULA', applyToType, '| minutes=', minutes, '|', formulaUsed, '| => fineAmount=', result);
            return result;
        }

        const calcType =
            fineConfig.calculationType === 'fixedPerHour' ? 'fixedPerHour' : 'shiftBased';
        console.log(testTag, applyToType, '| path=defaultFormula (fineRules empty) | calcType=', calcType);
        if (calcType === 'fixedPerHour') {
            const hours = minutes / 60;
            const baseNet = dailySalary != null && Number(dailySalary) > 0 ? Number(dailySalary) : 0;
            let finePerHour = 0;
            if (shiftHours > 0 && baseNet > 0) {
                finePerHour = baseNet / shiftHours;
            }
            if (finePerHour <= 0 && fineConfig.finePerHour != null && fineConfig.finePerHour > 0) {
                finePerHour = Number(fineConfig.finePerHour);
            }
            amount = finePerHour * hours;
            formulaUsed = `fixedPerHour: finePerHour = max(net/shiftHours, config.finePerHour) × (minutes÷60) | finePerHour=${finePerHour.toFixed(4)} × ${hours.toFixed(4)}`;
            console.log(testTag, applyToType, '|', formulaUsed, '| product=', amount.toFixed(6));
        } else if (calcType === 'shiftBased' && grossBase > 0 && shiftHours > 0) {
            const hourlyRate = grossBase / shiftHours;
            const hours = minutes / 60;
            amount = hourlyRate * hours;
            formulaUsed = `shiftBased: Fine = (DailyGross÷ShiftHours) × (Minutes÷60) = (${grossBase}÷${shiftHours}) × (${minutes}÷60)`;
            console.log(
                testTag,
                applyToType,
                '| hourlyRate=', hourlyRate.toFixed(6),
                '| minuteHours=', hours.toFixed(6),
                '| product(hourlyRate×minuteHours)=', amount.toFixed(6)
            );
            console.log(testTag, applyToType, '|', `${formulaUsed} = ${hourlyRate.toFixed(4)} × ${hours.toFixed(4)}`);
        } else {
            formulaUsed = `no formula applied: calcType=${calcType} dailySalary=${dailySalary} shiftHours=${shiftHours}`;
            console.log(testTag, applyToType, '|', formulaUsed);
        }
    }

    const result = Math.round((amount || 0) * 100) / 100;
    if ((amount || 0) > 0 && Number(shiftHours) > 0 && Number(minutes) > 0) {
        const baseDailySalary = Number(grossBase) > 0 ? Number(grossBase) : (Number(dailySalary) || 0);
        const minuteHours = Number(minutes) / 60;
        const perHourRate = baseDailySalary / Number(shiftHours);
        console.log(
            testTag,
            applyToType,
            '| Fine = (Daily Salary ÷ Shift Hours) × (Minutes ÷ 60)',
            `= (${baseDailySalary} ÷ ${shiftHours}) × (${minutes} ÷ 60)`,
            `= ${perHourRate.toFixed(6)} × ${minuteHours.toFixed(6)}`,
            `= ${(perHourRate * minuteHours).toFixed(6)}`,
            '| roundedFine=',
            result
        );
    }
    console.log(logPrefix, 'FORMULA', applyToType, '| minutes=', minutes, '|', formulaUsed, '| => fineAmount=', result);
    console.log(testTag, applyToType, '| FINAL round2dp:', (amount || 0), '→ fineAmount=', result);
    return result;
}

/**
 * Overtime pay (rupees) using the same base formula as fine when rules are empty:
 * shiftBased: (Daily Salary ÷ Shift Hours) × (Minutes ÷ 60); fixedPerHour: finePerHour × (minutes÷60).
 * Does not apply fineRules (late/early applyTo); use when payroll fine calculation is enabled.
 * @param {number} minutes - OT minutes to pay (already passed threshold checks)
 * @param {Object} fineConfig - From getEffectiveFineConfig
 * @param {number} dailySalary
 * @param {number} shiftHours
 * @param {number} [multiplier=1] - e.g. company overtime default multiplier
 * @returns {number}
 */
function calculateOvertimePayAmount(minutes, fineConfig, dailySalary, shiftHours, multiplier = 1) {
    const logPrefix = '[OT Pay][formula]';
    const m = Number(multiplier) > 0 ? Number(multiplier) : 1;
    if (!fineConfig || !fineConfig.enabled || minutes <= 0) {
        console.log(logPrefix, 'SKIP overtimeAmount=0 | reason=%s | minutes=%s enabled=%s',
            !fineConfig ? 'noConfig' : !fineConfig.enabled ? 'configDisabled' : 'nonPositiveMinutes',
            minutes,
            !!(fineConfig && fineConfig.enabled));
        return 0;
    }
    if (dailySalary == null || dailySalary <= 0 || shiftHours == null || shiftHours <= 0) {
        console.log(logPrefix, 'SKIP overtimeAmount=0 | reason=missingSalaryOrShiftHours', { dailySalary, shiftHours, minutes });
        return 0;
    }
    const calcType = fineConfig.calculationType === 'fixedPerHour' ? 'fixedPerHour' : 'shiftBased';
    let amount = 0;
    let formulaLine = '';
    if (calcType === 'fixedPerHour' && fineConfig.finePerHour != null && fineConfig.finePerHour > 0) {
        const hours = minutes / 60;
        amount = fineConfig.finePerHour * hours;
        formulaLine = `fixedPerHour: overtimeAmount = finePerHour × (OTminutes÷60) = ${fineConfig.finePerHour} × (${minutes}÷60) = ${fineConfig.finePerHour} × ${hours.toFixed(4)}`;
        console.log(logPrefix, 'type=fixedPerHour | OTminutes=%s | OT_hours=%s | finePerHour=%s | baseAmount(before mult)=%s',
            minutes, hours.toFixed(4), fineConfig.finePerHour, amount.toFixed(4));
    } else {
        const hourlyRate = dailySalary / shiftHours;
        const hours = minutes / 60;
        amount = hourlyRate * hours;
        formulaLine = `shiftBased: overtimeAmount = (dailySalary÷shiftHours) × (OTminutes÷60) = (${dailySalary}÷${shiftHours}) × (${minutes}÷60) = ${hourlyRate.toFixed(4)} × ${hours.toFixed(4)}`;
        console.log(logPrefix, 'type=shiftBased | dailySalary=%s | shiftHours=%s | hourlyRate=%s | OTminutes=%s | OT_hours=%s | baseAmount(before mult)=%s',
            dailySalary, shiftHours, hourlyRate.toFixed(4), minutes, hours.toFixed(4), amount.toFixed(4));
    }
    const result = Math.round(amount * m * 100) / 100;
    console.log(logPrefix, '%s | multiplier=%s | final = base×mult = %s × %s = %s',
        formulaLine, m, (amount).toFixed(4), m, result);
    return result;
}

/**
 * Apply a single fine rule: type '1xSalary'|'2xSalary'|'3xSalary'|'halfDay'|'fullDay'|'custom'.
 * @param {Object} rule - { type, customAmount?, customAmountUnit?, applyTo? }
 * @param {number} minutes - Late or early minutes
 * @param {number} dailySalary - Daily salary
 * @param {number} shiftHours - Shift hours
 * @returns {number} Fine amount
 */
function applyRuleAmount(rule, minutes, dailySalary, shiftHours) {
    if (!rule || !rule.type) return 0;
    const hourlyRate = shiftHours > 0 && dailySalary != null ? dailySalary / shiftHours : 0;
    const hours = minutes / 60;

    switch (String(rule.type).toLowerCase()) {
        case 'custom': {
            const amount = rule.customAmount ?? 0;
            const unit = (rule.customAmountUnit || 'perHour').toLowerCase();
            if (unit === 'perminute') return amount * minutes;
            if (unit === 'perhour') return amount * hours;
            if (unit === 'fixed') return amount;
            return amount * hours;
        }
        case '1xsalary':
            return hourlyRate * hours;
        case '2xsalary':
            return 2 * hourlyRate * hours;
        case '3xsalary':
            return 3 * hourlyRate * hours;
        case 'halfday':
            // Web parity: 0.5 × hourlyRate × hours (proportional to late/early duration)
            return hourlyRate * hours * 0.5;
        case 'fullday': {
            const ds = dailySalary != null ? Number(dailySalary) : 0;
            if (ds <= 0) return 0;
            const sh = Number(shiftHours) || 0;
            if (sh <= 0) return ds;
            if (hours >= sh) return ds;
            return ds * (hours / sh);
        }
        default:
            return hourlyRate * hours;
    }
}

module.exports = {
    getEffectiveFineConfig,
    calculateFineAmount,
    applyRuleAmount,
    calculateOvertimePayAmount,
    resolveFineDenominatorDays
};
