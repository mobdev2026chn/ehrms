/**
 * Fine calculation for attendance (check-in/check-out).
 * Uses only company.settings.payroll.fineCalculation (settings.payroll).
 * Formula (shiftBased): Fine = (Daily Salary ÷ Shift Hours) × (Late/Early Minutes ÷ 60)
 * When fineRules exist, applies matching rule by applyTo ('lateArrival' | 'earlyExit' | 'both').
 */

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
 * Formula: Fine = (Daily Salary ÷ Shift Hours) × (Minutes ÷ 60)
 * @param {number} minutes - Late or early minutes
 * @param {'lateArrival'|'earlyExit'} applyToType - For which type we're calculating
 * @param {Object} fineConfig - From getEffectiveFineConfig
 * @param {number} dailySalary - Daily salary for shift-based
 * @param {number} shiftHours - Shift duration in hours
 * @returns {number} Fine amount (>= 0)
 */
function calculateFineAmount(minutes, applyToType, fineConfig, dailySalary, shiftHours) {
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

    if (matchingRule) {
        const hourlyRate = shiftHours > 0 && dailySalary != null ? dailySalary / shiftHours : 0;
        const hours = minutes / 60;
        amount = applyRuleAmount(matchingRule, minutes, dailySalary, shiftHours);
        formulaUsed = `rule type=${matchingRule.type} applyTo=${matchingRule.applyTo || 'both'} | dailySalary=${dailySalary} shiftHours=${shiftHours} hourlyRate=${hourlyRate.toFixed(4)} minutes=${minutes} hours=${hours.toFixed(4)}`;
        const rt = String(matchingRule.type || '').toLowerCase();
        let ruleExpansion = '';
        if (rt === '1xsalary') {
            ruleExpansion = `1xSalary: (dailySalary÷shiftHours)×(minutes÷60) = (${dailySalary}÷${shiftHours})×(${minutes}÷60) = ${hourlyRate.toFixed(4)}×${hours.toFixed(4)} = ${(hourlyRate * hours).toFixed(4)}`;
        } else if (rt === '2xsalary') {
            ruleExpansion = `2xSalary: 2×(dailySalary÷shiftHours)×(minutes÷60) = 2×${hourlyRate.toFixed(4)}×${hours.toFixed(4)} = ${(2 * hourlyRate * hours).toFixed(4)}`;
        } else if (rt === '3xsalary') {
            ruleExpansion = `3xSalary: 3×(dailySalary÷shiftHours)×(minutes÷60) = 3×${hourlyRate.toFixed(4)}×${hours.toFixed(4)} = ${(3 * hourlyRate * hours).toFixed(4)}`;
        } else if (rt === 'halfday') {
            ruleExpansion = `halfDay: dailySalary÷2 = ${dailySalary != null ? (dailySalary / 2).toFixed(4) : '0'}`;
        } else if (rt === 'fullday') {
            ruleExpansion = `fullDay: dailySalary = ${dailySalary != null ? Number(dailySalary).toFixed(4) : '0'}`;
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
        if (calcType === 'fixedPerHour' && (fineConfig.finePerHour != null && fineConfig.finePerHour > 0)) {
            const hours = minutes / 60;
            amount = fineConfig.finePerHour * hours;
            formulaUsed = `fixedPerHour: Fine = finePerHour × (minutes÷60) = ${fineConfig.finePerHour} × (${minutes}÷60) = ${fineConfig.finePerHour} × ${hours.toFixed(4)}`;
            console.log(testTag, applyToType, '|', formulaUsed, '| product=', amount.toFixed(6));
        } else if (calcType === 'shiftBased' && dailySalary != null && shiftHours > 0) {
            const hourlyRate = dailySalary / shiftHours;
            const hours = minutes / 60;
            amount = hourlyRate * hours;
            formulaUsed = `shiftBased: Fine = (DailySalary÷ShiftHours) × (Minutes÷60) = (${dailySalary}÷${shiftHours}) × (${minutes}÷60)`;
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
            return dailySalary != null ? dailySalary / 2 : 0;
        case 'fullday':
            return dailySalary != null ? dailySalary : 0;
        default:
            return hourlyRate * hours;
    }
}

module.exports = {
    getEffectiveFineConfig,
    calculateFineAmount,
    applyRuleAmount,
    calculateOvertimePayAmount
};
