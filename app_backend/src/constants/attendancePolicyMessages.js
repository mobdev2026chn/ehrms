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

// Scenario 1: enabled + allocated > 0, break exceeded the allowance.
const breakExceeded = (exceededMinutes) =>
    `Allocated break time exceeded by ${Math.max(0, Math.round(Number(exceededMinutes) || 0))} minutes.\n`
    + `Exceeded minutes will be added to Fine.`;

// Scenario 2 & 4: allocated = 0 (enabled-but-unconfigured, or disabled-and-unconfigured).
const BREAK_NOT_CONFIGURED =
    'Break is not configured for your shift. Contact HR.\n'
    + 'Break duration will be processed with Fine.';

// Scenario 3: disabled + allocated > 0.
const BREAK_DISABLED =
    'Break is disabled for your shift.\n'
    + 'Contact HR to enable.\n'
    + 'Break duration will be processed with Fine.';

// ---- PERMISSION --------------------------------------------------------------

// Scenario 1: enabled + allocated > 0, permission exceeded the allowance.
const permissionExceeded = (exceededMinutes) =>
    `Allocated permission time exceeded by ${Math.max(0, Math.round(Number(exceededMinutes) || 0))} minutes.\n`
    + `Exceeded minutes will be processed with Fine.`;

// Scenario 2 & 4: allocated = 0.
const PERMISSION_NOT_CONFIGURED =
    'Permission is not configured for your shift. Contact HR.\n'
    + 'Permission duration will be processed with Fine.';

// Scenario 3: disabled + allocated > 0.
const PERMISSION_DISABLED =
    'Permission is disabled for your shift.\n'
    + 'Contact HR to enable.\n'
    + 'Permission duration will be processed with Fine.';

// ---- OVERTIME ----------------------------------------------------------------

// Buffer configured + overtime NOT allowed for the staff.
const OVERTIME_DISABLED = 'Overtime is disabled for you.';

// Buffer not configured (regardless of the staff overtime-allowed flag).
const OVERTIME_NOT_CONFIGURED = 'Overtime is not configured. Contact HR.';

/**
 * Resolve the break notice for a given policy state. Returns null when breaks are
 * normally configured (enabled + allowance > 0) and not exceeded — callers then use
 * breakExceeded() once an overage is known.
 *   enabledExplicit: true | false | null   (null = legacy/unconfigured, no notice)
 *   allocatedMinutes: configured allowedMinutes (before any fallback)
 */
function resolveBreakNotice({ enabledExplicit, allocatedMinutes }) {
    const alloc = Math.max(0, Number(allocatedMinutes) || 0);
    if (enabledExplicit === false) {
        return alloc > 0 ? BREAK_DISABLED : BREAK_NOT_CONFIGURED; // S3 / S4
    }
    if (enabledExplicit === true && alloc === 0) {
        return BREAK_NOT_CONFIGURED; // S2
    }
    return null; // S1 normal (use breakExceeded when over) or legacy null
}

/**
 * Resolve the permission notice for a given policy state. Returns null when
 * permission is normally configured (enabled + allowance > 0) and not exceeded.
 */
function resolvePermissionNotice({ enabledExplicit, allocatedMinutes }) {
    const alloc = Math.max(0, Number(allocatedMinutes) || 0);
    if (enabledExplicit === false) {
        return alloc > 0 ? PERMISSION_DISABLED : PERMISSION_NOT_CONFIGURED; // S3 / S4
    }
    if (enabledExplicit === true && alloc === 0) {
        return PERMISSION_NOT_CONFIGURED; // S2
    }
    return null; // S1 normal (use permissionExceeded when over) or legacy null
}

module.exports = {
    breakExceeded,
    BREAK_NOT_CONFIGURED,
    BREAK_DISABLED,
    permissionExceeded,
    PERMISSION_NOT_CONFIGURED,
    PERMISSION_DISABLED,
    OVERTIME_DISABLED,
    OVERTIME_NOT_CONFIGURED,
    resolveBreakNotice,
    resolvePermissionNotice,
};
