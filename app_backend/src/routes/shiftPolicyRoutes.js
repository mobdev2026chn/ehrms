const express = require('express');
const router = express.Router();
const { protect, authorizeRoles } = require('../middleware/authMiddleware');
const { getShiftPolicies, updateShiftPolicies } = require('../controllers/shiftPolicyController');

// Admin/HR only: manage per-shift break/permission/overtime policies on the attendance template.
const ADMIN_ROLES = ['Admin', 'Developer', 'HR', 'SuperAdmin', 'Super Admin'];

router.get('/', protect, authorizeRoles(...ADMIN_ROLES), getShiftPolicies);
router.put('/:shiftId', protect, authorizeRoles(...ADMIN_ROLES), updateShiftPolicies);

module.exports = router;
