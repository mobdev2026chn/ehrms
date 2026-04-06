const mongoose = require('mongoose');
const SalaryTemplate = require('../models/SalaryTemplate');
const SalaryPayableDaysRule = require('../models/SalaryPayableDaysRule');

/**
 * Same denominator as web `resolveTemplatePayableDays` in payroll.controller.ts (TypeScript):
 * only SalaryTemplate.payableDaysRule with type `fixedDays` + daysPerMonth uses a fixed divisor;
 * `calendarMonth` (or missing rule) uses full-month working-day count.
 */
async function resolveTemplateLinkedPayableDenominatorDays({
    staff,
    company,
    fullMonthWorkingDays,
}) {
    const fallback = Number(fullMonthWorkingDays) || 0;
    const businessId = staff?.businessId || company?._id;
    const templateId = staff?.salaryTemplateId;
    if (!templateId || !mongoose.Types.ObjectId.isValid(String(templateId))) {
        return fallback;
    }
    if (!businessId || !mongoose.Types.ObjectId.isValid(String(businessId))) {
        return fallback;
    }
    try {
        const template = await SalaryTemplate.findOne({
            _id: new mongoose.Types.ObjectId(String(templateId)),
            businessId: new mongoose.Types.ObjectId(String(businessId)),
            isActive: true,
        })
            .select('payableDaysRuleId')
            .lean();
        if (!template?.payableDaysRuleId) return fallback;
        const rule = await SalaryPayableDaysRule.findOne({
            _id: template.payableDaysRuleId,
            businessId: new mongoose.Types.ObjectId(String(businessId)),
        })
            .select('type daysPerMonth')
            .lean();
        if (!rule) return fallback;
        const t = String(rule.type || '').trim().toLowerCase();
        const dpm = Number(rule.daysPerMonth) || 0;
        if (t === 'fixeddays' && dpm > 0) return dpm;
        return fallback;
    } catch (_) {
        return fallback;
    }
}

/**
 * Resolve payable-days rule from staff/company settings.
 *
 * Normalized rule keys:
 * - present_only
 * - present_plus_paid_leave
 *
 * Optional denominator:
 * - fixedDays -> use `daysPerMonth` (e.g. 30)
 */

function normalizePayableDaysRule(rawRule) {
    if (rawRule == null) return null;
    const v = String(rawRule).trim().toLowerCase();
    if (!v) return null;

    if (
        v.includes('present_plus_paid_leave') ||
        v.includes('present+paidleave') ||
        v.includes('present_paid_leave') ||
        v.includes('present and paid leave') ||
        v.includes('effectivepaiddays') ||
        v.includes('paidleave')
    ) {
        return 'present_plus_paid_leave';
    }
    if (
        v.includes('present_only') ||
        v === 'present' ||
        v.includes('present days')
    ) {
        return 'present_only';
    }
    return null;
}

function extractRuleCandidate(value) {
    if (value == null) return null;
    if (typeof value === 'string' || typeof value === 'number') return value;
    if (typeof value === 'object') {
        return (
            value.code ||
            value.key ||
            value.value ||
            value.rule ||
            value.name ||
            value._id ||
            null
        );
    }
    return null;
}

function parseInlineRuleConfig(rawValue) {
    if (!rawValue || typeof rawValue !== 'object') return null;
    const type = String(rawValue.type || '').trim().toLowerCase();
    const daysPerMonth = Number(rawValue.daysPerMonth) || 0;
    if (type === 'fixeddays' && daysPerMonth > 0) {
        return {
            denominatorType: 'fixed_days',
            denominatorDays: daysPerMonth,
        };
    }
    return null;
}

async function loadRuleDocumentFromDb({ businessId, candidates }) {
    // Source of truth provided by user: salarypayabledaysrules collection.
    const collection = mongoose.connection?.db?.collection('salarypayabledaysrules');
    if (!collection) return null;

    const strCandidates = candidates
        .map((v) => extractRuleCandidate(v))
        .filter((v) => v != null)
        .map((v) => String(v).trim())
        .filter(Boolean);

    const objectIdCandidates = strCandidates
        .filter((v) => mongoose.Types.ObjectId.isValid(v))
        .map((v) => new mongoose.Types.ObjectId(v));

    const or = [];
    if (objectIdCandidates.length) or.push({ _id: { $in: objectIdCandidates } });
    if (strCandidates.length) {
        or.push({ key: { $in: strCandidates } });
        or.push({ title: { $in: strCandidates } });
    }
    if (!or.length) return null;

    const query = { $or: or };
    if (businessId && mongoose.Types.ObjectId.isValid(String(businessId))) {
        query.businessId = new mongoose.Types.ObjectId(String(businessId));
    }

    return await collection.findOne(query, { sort: { updatedAt: -1 } });
}

async function loadTemplateDerivedRuleCandidates({ businessId, candidates }) {
    const db = mongoose.connection?.db;
    if (!db) return [];

    const rawValues = candidates
        .map((v) => extractRuleCandidate(v))
        .filter((v) => v != null)
        .map((v) => String(v).trim())
        .filter(Boolean);
    const rawIds = rawValues
        .filter((v) => mongoose.Types.ObjectId.isValid(v))
        .map((v) => new mongoose.Types.ObjectId(v));
    if (!rawValues.length) return [];

    const templateCollections = [
        // likely names
        'salarytemplates',
        'salarytemplate',
        'staffsalarytemplates',
    ];

    const out = [];
    for (const colName of templateCollections) {
        try {
            const col = db.collection(colName);
            const query = {};
            const or = [];
            if (rawIds.length) {
                or.push({ _id: { $in: rawIds } });
            }
            // Web legacy templateKey support.
            or.push({ templateKey: { $in: rawValues } });
            or.push({ key: { $in: rawValues } });
            query.$or = or;
            if (businessId && mongoose.Types.ObjectId.isValid(String(businessId))) {
                query.businessId = new mongoose.Types.ObjectId(String(businessId));
            }
            const rows = await col
                .find(query, { projection: { payableDaysRuleId: 1, payableDaysRule: 1, ruleId: 1, key: 1, title: 1 } })
                .toArray();
            for (const r of rows) {
                if (!r || typeof r !== 'object') continue;
                if (r.payableDaysRuleId != null) out.push(r.payableDaysRuleId);
                if (r.payableDaysRule != null) out.push(r.payableDaysRule);
                if (r.ruleId != null) out.push(r.ruleId);
                // Some templates may directly keep key/title of salarypayabledaysrules.
                if (r.key != null) out.push(r.key);
                if (r.title != null) out.push(r.title);
            }
        } catch (_) {
            // ignore missing collections
        }
    }

    return out;
}

async function loadAssignedStaffTemplateRule({ businessId, staffId }) {
    const db = mongoose.connection?.db;
    if (!db || staffId == null || !mongoose.Types.ObjectId.isValid(String(staffId))) {
        return null;
    }
    try {
        const col = db.collection('salarytemplates');
        const query = {
            assignedStaff: new mongoose.Types.ObjectId(String(staffId)),
        };
        if (businessId && mongoose.Types.ObjectId.isValid(String(businessId))) {
            query.businessId = new mongoose.Types.ObjectId(String(businessId));
        }
        const template = await col.findOne(
            query,
            {
                sort: { updatedAt: -1 },
                projection: { _id: 1, payableDaysRuleId: 1 },
            }
        );
        if (!template) return null;
        return {
            templateId: template._id,
            payableDaysRuleId: template.payableDaysRuleId,
        };
    } catch (_) {
        return null;
    }
}

async function loadPayrollConfigRuleCandidate({ businessId }) {
    const db = mongoose.connection?.db;
    if (!db || businessId == null || !mongoose.Types.ObjectId.isValid(String(businessId))) {
        return null;
    }
    try {
        const col = db.collection('salarypayrollconfigs');
        const cfg = await col.findOne(
            { businessId: new mongoose.Types.ObjectId(String(businessId)) },
            { projection: { activePayableDaysRuleId: 1 } }
        );
        if (!cfg) return null;
        return cfg.activePayableDaysRuleId || null;
    } catch (_) {
        return null;
    }
}

async function resolvePayableDaysConfig({ staff, company }) {
    const defaultRule = 'present_plus_paid_leave';
    const candidates = [
        staff?.payableDaysRuleId,
        staff?.payableDaysRule,
        // Raw template id/key from staff (common persisted form).
        staff?.salaryTemplateId,
        staff?.salary?.payableDaysRuleId,
        staff?.salary?.payableDaysRule,
        staff?.salaryTemplateId?.payableDaysRuleId,
        staff?.salaryTemplateId?.payableDaysRule,
        staff?.salaryTemplate?.payableDaysRuleId,
        staff?.salaryTemplate?.payableDaysRule,
        company?.settings?.payroll?.payableDaysRuleId,
        company?.settings?.payroll?.payableDaysRule,
        company?.settings?.payroll?.calculationLogic,
    ];
    const templateDerivedCandidates = await loadTemplateDerivedRuleCandidates({
        businessId: staff?.businessId || company?._id,
        candidates,
    });
    const assignedTemplateRule = await loadAssignedStaffTemplateRule({
        businessId: staff?.businessId || company?._id,
        staffId: staff?._id,
    });
    const payrollConfigRuleCandidate = await loadPayrollConfigRuleCandidate({
        businessId: staff?.businessId || company?._id,
    });
    const allCandidates = [...candidates, ...templateDerivedCandidates];
    if (assignedTemplateRule?.payableDaysRuleId != null) {
        allCandidates.push(assignedTemplateRule.payableDaysRuleId);
    }
    if (payrollConfigRuleCandidate != null) {
        allCandidates.push(payrollConfigRuleCandidate);
    }

    let rule = null;
    let denominatorDays = null;
    let denominatorType = 'working_days_full_month';
    let resolvedTemplateId = assignedTemplateRule?.templateId ?? null;
    let resolvedRuleId =
        assignedTemplateRule?.payableDaysRuleId ??
        payrollConfigRuleCandidate ??
        null;

    for (const c of allCandidates) {
        const normalized = normalizePayableDaysRule(extractRuleCandidate(c));
        if (normalized) {
            rule = normalized;
            break;
        }
    }

    for (const c of allCandidates) {
        const inline = parseInlineRuleConfig(c);
        if (inline) {
            denominatorType = inline.denominatorType;
            denominatorDays = inline.denominatorDays;
            break;
        }
    }

    if (denominatorDays == null) {
        const doc = await loadRuleDocumentFromDb({
            businessId: staff?.businessId || company?._id,
            candidates: allCandidates,
        });
        if (doc) {
            resolvedRuleId = doc._id || resolvedRuleId;
            const normalizedDocRule = normalizePayableDaysRule(
                extractRuleCandidate(doc)
            );
            if (normalizedDocRule) rule = normalizedDocRule;
            const type = String(doc.type || '').trim().toLowerCase();
            const dpm = Number(doc.daysPerMonth) || 0;
            if (type === 'fixeddays' && dpm > 0) {
                denominatorType = 'fixed_days';
                denominatorDays = dpm;
            }
        }
    }

    if (!rule) rule = defaultRule;

    return {
        rule,
        denominatorType,
        denominatorDays: denominatorDays != null && denominatorDays > 0 ? denominatorDays : null,
        resolvedTemplateId,
        resolvedRuleId,
    };
}

async function resolvePayableDaysRule({ staff, company }) {
    const cfg = await resolvePayableDaysConfig({ staff, company });
    return cfg.rule;
}

function resolvePayableBaseDays({ config, fallbackDays = 0 }) {
    const fb = Number(fallbackDays) || 0;
    if (config?.denominatorType === 'fixed_days' && Number(config?.denominatorDays) > 0) {
        return Number(config.denominatorDays);
    }
    return fb;
}

function computePayableDays({ presentDays = 0, paidLeaveDays = 0, rule }) {
    const p = Number(presentDays) || 0;
    const pl = Number(paidLeaveDays) || 0;
    if (rule === 'present_only') return p;
    return p + pl;
}

module.exports = {
    resolvePayableDaysConfig,
    resolvePayableDaysRule,
    resolvePayableBaseDays,
    computePayableDays,
    resolveTemplateLinkedPayableDenominatorDays,
};

