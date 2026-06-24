/**
 * Canonical user-facing messages for the attendance policy (break / permission /
 * overtime). These are the SINGLE source of truth for the exact wording the apps
 * (EHRMS app + face kiosk) surface as tooltips / notices / snackbars. The backend
 * returns these strings in API responses so every client shows identical wording
 * instead of hand-building near-duplicates that drift.
 *
 * Wording matches the attendance policy spec verbatim. Multi-line notices use "\n"
 * (the apps already render break notices with line breaks).
 */

// ---- BREAK -------------------------------------------------------------------
// The four policy scenarios, keyed on (enabled, allocatedMinutes):
//   S1  enabled  + minutes > 0  -> informational: within allowance is free,
//                                  break taken beyond the set minutes is Fine.
//   S2  enabled  + minutes = 0  -> any break is Fine; contact HR.
//   S3  disabled + minutes > 0  -> any break is Fine; contact HR.
//   S4  disabled + minutes = 0  -> not configured; contact HR; Fine calculated.

// Scenario 1 (informational, before any overage): the configured allowance and
// the rule that anything beyond it is fined.
const breakWithinAllowance = (allocatedMinutes) => {
    const min = Math.max(0, Math.round(Number(allocatedMinutes) || 0));
    return `Break allowed for ${min} minutes.\n`
        + `Break taken beyond ${min} minutes will be considered as Fine.`;
};

// Scenario 1 (after the fact): break exceeded the allowance by N minutes.
const breakExceeded = (exceededMinutes) =>
    `Allocated break time exceeded by ${Math.max(0, Math.round(Number(exceededMinutes) || 0))} minutes.\n`
    + `Exceeded minutes will be added to Fine.`;

// Scenario 2 (enabled + 0) & Scenario 3 (disabled + minutes): breaks are allowed
// but every minute is fined.
const BREAK_TAKEN_AS_FINE =
    'Break taken will be considered as Fine.\n'
    + 'Contact HR.';

// Scenario 4: disabled + allocated = 0 → not configured.
const BREAK_NOT_CONFIGURED =
    'Break is not configured for your shift. Contact HR.\n'
    + 'Fine will be calculated.';

// ---- PERMISSION --------------------------------------------------------------
// Same four scenarios as Break (keyed on enabled + allocatedMinutes).

// Scenario 1 (informational, before any overage).
const permissionWithinAllowance = (allocatedMinutes) => {
    const min = Math.max(0, Math.round(Number(allocatedMinutes) || 0));
    return `Permission allowed for ${min} minutes.\n`
        + `Permission taken beyond ${min} minutes will be considered as Fine.`;
};

// Scenario 1 (after the fact): permission exceeded the allowance by N minutes.
const permissionExceeded = (exceededMinutes) =>
    `Allocated permission time exceeded by ${Math.max(0, Math.round(Number(exceededMinutes) || 0))} minutes.\n`
    + `Exceeded minutes will be processed with Fine.`;

// Scenario 2 (enabled + 0) & Scenario 3 (disabled + minutes): any permission is fined.
const PERMISSION_TAKEN_AS_FINE =
    'Permission taken will be considered as Fine.\n'
    + 'Contact HR.';

// Scenario 4: disabled + allocated = 0 → not configured.
const PERMISSION_NOT_CONFIGURED =
    'Permission is not configured for your shift. Contact HR.\n'
    + 'Fine will be calculated.';

// ---- OVERTIME ----------------------------------------------------------------

// Buffer configured + overtime NOT allowed for the staff.
const OVERTIME_DISABLED = 'Overtime is disabled for you.';

// Buffer not configured (regardless of the staff overtime-allowed flag).
const OVERTIME_NOT_CONFIGURED = 'Overtime is not configured. Contact HR.';

/**
 * Resolve the break notice for a given policy state. Returns the informational
 * within-allowance notice for the normal case (S1) so the employee always sees
 * the configured allowance + fine rule; callers swap in breakExceeded() once an
 * actual overage is known.
 *   enabledExplicit: true | false | null   (null = legacy/unconfigured, no notice)
 *   allocatedMinutes: configured allowedMinutes (before any fallback)
 */
function resolveBreakNotice({ enabledExplicit, allocatedMinutes }) {
    const alloc = Math.max(0, Number(allocatedMinutes) || 0);
    if (enabledExplicit === false) {
        return alloc > 0 ? BREAK_TAKEN_AS_FINE : BREAK_NOT_CONFIGURED; // S3 / S4
    }
    if (enabledExplicit === true) {
        return alloc > 0 ? breakWithinAllowance(alloc) : BREAK_TAKEN_AS_FINE; // S1 / S2
    }
    return null; // legacy/unknown (enabledExplicit null) → no notice
}

/**
 * Resolve the permission notice for a given policy state. Mirrors the break
 * scenarios: S1 returns the informational within-allowance notice.
 */
function resolvePermissionNotice({ enabledExplicit, allocatedMinutes }) {
    const alloc = Math.max(0, Number(allocatedMinutes) || 0);
    if (enabledExplicit === false) {
        return alloc > 0 ? PERMISSION_TAKEN_AS_FINE : PERMISSION_NOT_CONFIGURED; // S3 / S4
    }
    if (enabledExplicit === true) {
        return alloc > 0 ? permissionWithinAllowance(alloc) : PERMISSION_TAKEN_AS_FINE; // S1 / S2
    }
    return null; // legacy/unknown (enabledExplicit null) → no notice
}

module.exports = {
    breakWithinAllowance,
    breakExceeded,
    BREAK_TAKEN_AS_FINE,
    BREAK_NOT_CONFIGURED,
    permissionWithinAllowance,
    permissionExceeded,
    PERMISSION_TAKEN_AS_FINE,
    PERMISSION_NOT_CONFIGURED,
    OVERTIME_DISABLED,
    OVERTIME_NOT_CONFIGURED,
    resolveBreakNotice,
    resolvePermissionNotice,
};
