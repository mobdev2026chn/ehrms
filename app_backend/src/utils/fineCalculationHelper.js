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
    const matchingRule = rules.find((r) => applyToMatch(r.applyTo));

    let amount = 0;
    let formulaUsed = '';

    if (matchingRule) {
        const hourlyRate = shiftHours > 0 && dailySalary != null ? dailySalary / shiftHours : 0;
        const hours = minutes / 60;
        amount = applyRuleAmount(matchingRule, minutes, dailySalary, shiftHours);
        formulaUsed = `rule type=${matchingRule.type} applyTo=${matchingRule.applyTo || 'both'} | dailySalary=${dailySalary} shiftHours=${shiftHours} hourlyRate=${hourlyRate.toFixed(2)} minutes=${minutes} hours=${hours.toFixed(2)}`;
    } else {
        // IMPORTANT business rule:
        // - If fineRules are provided and none match this action (lateArrival/earlyExit),
        //   DO NOT apply default formula for this action.
        // - Default formula fallback is used only when fineRules are empty.
        if (rules.length > 0) {
            formulaUsed = `rule-miss: fineRules exist but none match applyTo=${applyToType}; fineAmount=0`;
            const result = 0;
            console.log(logPrefix, 'FORMULA', applyToType, '| minutes=', minutes, '|', formulaUsed, '| => fineAmount=', result);
            return result;
        }

        const calcType =
            fineConfig.calculationType === 'fixedPerHour' ? 'fixedPerHour' : 'shiftBased';
        if (calcType === 'fixedPerHour' && (fineConfig.finePerHour != null && fineConfig.finePerHour > 0)) {
            const hours = minutes / 60;
            amount = fineConfig.finePerHour * hours;
            formulaUsed = `fixedPerHour: Fine = finePerHour × (minutes÷60) = ${fineConfig.finePerHour} × (${minutes}÷60) = ${fineConfig.finePerHour} × ${hours.toFixed(2)}`;
        } else if (calcType === 'shiftBased' && dailySalary != null && shiftHours > 0) {
            const hourlyRate = dailySalary / shiftHours;
            const hours = minutes / 60;
            amount = hourlyRate * hours;
            formulaUsed = `shiftBased: Fine = (DailySalary÷ShiftHours) × (Minutes÷60) = (${dailySalary}÷${shiftHours}) × (${minutes}÷60) = ${hourlyRate.toFixed(2)} × ${hours.toFixed(2)}`;
        } else {
            formulaUsed = `no formula applied: calcType=${calcType} dailySalary=${dailySalary} shiftHours=${shiftHours}`;
        }
    }

    const result = Math.round((amount || 0) * 100) / 100;
    console.log(logPrefix, 'FORMULA', applyToType, '| minutes=', minutes, '|', formulaUsed, '| => fineAmount=', result);
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
    applyRuleAmount
};
