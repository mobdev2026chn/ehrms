const Customer = require('../models/Customer');

const MSG_DUP_PHONE = 'Customer already exists with this phone number.';
const MSG_DUP_EMAIL = 'Customer already exists with this email address.';
const MSG_DUP_GENERIC = 'Customer already exists with this email or phone number.';

function normalizeCustomerNumber(value) {
  if (value == null || value === '') return '';
  return String(value).replace(/\D/g, '').trim();
}

function normalizeEmailId(value) {
  if (value == null || value === '') return '';
  return String(value).trim().toLowerCase();
}

/** User-friendly messages for create/update failures (avoid opaque "Server Error"). */
function customerSaveErrorResponse(error) {
  const code = error?.code;
  const name = error?.name;

  const msgStr = String(error?.message || '');
  if (code === 11000 || msgStr.includes('E11000') || msgStr.includes('duplicate key')) {
    const key = error.keyPattern || error.keyValue || {};
    const fields = Object.keys(key);
    if (fields.includes('customerNumber') || msgStr.includes('customerNumber')) {
      return { status: 409, body: { success: false, message: MSG_DUP_PHONE } };
    }
    if (fields.includes('emailId') || msgStr.includes('emailId')) {
      return { status: 409, body: { success: false, message: MSG_DUP_EMAIL } };
    }
    return { status: 409, body: { success: false, message: MSG_DUP_GENERIC } };
  }

  if (name === 'ValidationError' && error.errors) {
    return { status: 400, body: { success: false, message: validationErrorUserMessage(error) } };
  }

  return null;
}

function validationErrorUserMessage(error) {
  const fieldLabels = {
    customerName: 'customer name',
    customerNumber: 'phone number',
    emailId: 'email',
    address: 'address',
    city: 'city',
    pincode: 'pincode',
    addedBy: 'account',
    businessId: 'company',
  };
  for (const [path, err] of Object.entries(error.errors)) {
    const label = fieldLabels[path] || path.replace(/([A-Z])/g, ' $1').trim().toLowerCase();
    if (err?.kind === 'required' || /required/i.test(String(err?.message || ''))) {
      return `Please enter ${label}.`;
    }
    if (err?.kind === 'enum') {
      return `Please choose a valid option for ${label}.`;
    }
  }
  return 'Please check the form and try again.';
}

/**
 * @returns {Promise<{ message: string } | null>}
 */
async function findDuplicateCustomerConflict({ businessId, customerNumber, emailId, excludeCustomerId }) {
  const phone = normalizeCustomerNumber(customerNumber);
  const email = normalizeEmailId(emailId);
  if (phone) {
    const q = { businessId, customerNumber: phone };
    if (excludeCustomerId) q._id = { $ne: excludeCustomerId };
    const byPhone = await Customer.findOne(q).select('_id').lean();
    if (byPhone) return { message: MSG_DUP_PHONE };
  }
  if (email) {
    const q = { businessId, emailId: email };
    if (excludeCustomerId) q._id = { $ne: excludeCustomerId };
    const byEmail = await Customer.findOne(q).select('_id').lean();
    if (byEmail) return { message: MSG_DUP_EMAIL };
  }
  return null;
}

function isPrivilegedUser(req) {
  // HR/Admin/Super Admin should see all customers.
  // Employees must be restricted by `visibleToStaffIds`.
  return Boolean(req.user?.role && req.user.role !== 'Employee');
}

function buildVisibleToStaffOnlyQuery({ staffId }) {
  // Strict visibility:
  // - visibleToStaffIds missing/empty => NOT visible to anyone
  // - visibleToStaffIds contains staffId => visible to that staff
  if (!staffId) return { visibleToStaffIds: { $in: [] } };
  return { visibleToStaffIds: { $in: [staffId] } };
}

exports.createCustomer = async (req, res) => {
  try {
    const businessId = req.staff?.businessId;
    // Schema `addedBy` refs User; prefer JWT user id. Legacy tokens may only resolve Staff — fall back to staff._id.
    const addedBy = req.user?._id || req.staff?._id;
    if (!businessId) {
      return res.status(400).json({
        success: false,
        message: 'Company information is missing. Please log in again or contact support.',
      });
    }
    if (!addedBy) {
      return res.status(400).json({
        success: false,
        message: 'Could not resolve your account. Please log in again.',
      });
    }
    const creatorStaffId = req.staff?._id;
    const privileged = isPrivilegedUser(req);

    let visibleToStaffIdsToSet = undefined;
    if (privileged) {
      // Default: only the creating staff should see it.
      const provided = Array.isArray(req.body.visibleToStaffIds) ? req.body.visibleToStaffIds : [];
      const providedList = provided.filter(Boolean);
      const creatorStr = creatorStaffId?.toString();
      const hasCreator =
        creatorStr && providedList.some((id) => id?.toString?.() === creatorStr);
      visibleToStaffIdsToSet =
        providedList.length > 0
          ? (hasCreator ? providedList : [...providedList, creatorStaffId])
          : (creatorStaffId ? [creatorStaffId] : []);
    } else {
      const provided = Array.isArray(req.body.visibleToStaffIds) ? req.body.visibleToStaffIds : [];
      const creatorStr = creatorStaffId?.toString();
      const providedList = provided.filter(Boolean);
      const hasCreator = creatorStr
        ? providedList.some((id) => id?.toString?.() === creatorStr)
        : false;

      if (!creatorStr) {
        // No staff context: safest is to show nothing to anyone.
        visibleToStaffIdsToSet = [];
      } else if (providedList.length === 0) {
        // Requirement: include creating staffId.
        visibleToStaffIdsToSet = [creatorStaffId];
      } else if (hasCreator) {
        visibleToStaffIdsToSet = providedList;
      } else {
        visibleToStaffIdsToSet = [...providedList, creatorStaffId];
      }
    }

    const payload = {
      ...req.body,
      businessId,
      addedBy: addedBy || req.body.addedBy,
      source: 'app',
      visibleToStaffIds: visibleToStaffIdsToSet,
    };
    if (payload.customerNumber != null && String(payload.customerNumber).trim() !== '') {
      payload.customerNumber = normalizeCustomerNumber(payload.customerNumber);
    }
    if (payload.emailId != null && String(payload.emailId).trim() !== '') {
      payload.emailId = normalizeEmailId(payload.emailId);
    }

    const duplicate = await findDuplicateCustomerConflict({
      businessId,
      customerNumber: payload.customerNumber,
      emailId: payload.emailId,
      excludeCustomerId: null,
    });
    if (duplicate) {
      return res.status(409).json({ success: false, message: duplicate.message });
    }

    const newCustomer = new Customer(payload);
    await newCustomer.save();
    res.status(201).json(newCustomer.toObject ? newCustomer.toObject() : newCustomer);
  } catch (error) {
    console.error('Error creating customer:', error);
    const mapped = customerSaveErrorResponse(error);
    if (mapped) {
      return res.status(mapped.status).json(mapped.body);
    }
    res.status(500).json({
      success: false,
      message: 'Could not save customer. Please try again.',
    });
  }
};

exports.getAllCustomers = async (req, res) => {
  try {
    const businessId = req.staff?.businessId;
    if (!businessId) {
      console.log('[Customers] GET /customers - no businessId on staff, returning empty');
      return res.status(200).json([]);
    }

    const staffId = req.staff?._id;

    const filter = {
      businessId,
      ...buildVisibleToStaffOnlyQuery({ staffId }),
    };

    console.log('[Customers] GET /customers - fetching with filter:', {
      businessId: businessId.toString(),
      staffId: staffId ? staffId.toString() : null,
    });

    const customers = await Customer.find(filter).sort({ customerName: 1 }).lean();
    console.log('[Customers] Fetched', customers.length, 'customer(s)');
    res.status(200).json(customers);
  } catch (error) {
    console.error('[Customers] Error fetching customers:', error);
    res.status(500).json({
      success: false,
      message: 'Could not load customers. Please try again.',
    });
  }
};

exports.getCustomerById = async (req, res) => {
  try {
    const customerId = req.params.id;
    const businessId = req.staff?.businessId;

    if (!businessId) {
      return res.status(404).json({ success: false, message: 'Customer not found.' });
    }

    const staffId = req.staff?._id;

    const filter = {
      _id: customerId,
      businessId,
      ...buildVisibleToStaffOnlyQuery({ staffId }),
    };

    console.log('[Customers] GET /customers/:id - customerId:', customerId);
    const customer = await Customer.findOne(filter).lean();
    if (!customer) {
      console.log('[Customers] Customer not found:', customerId);
      return res.status(404).json({ success: false, message: 'Customer not found.' });
    }

    console.log('[Customers] Fetched customer:', customer.customerName || customerId);
    res.status(200).json(customer);
  } catch (error) {
    console.error('[Customers] Error fetching customer by ID:', error);
    res.status(500).json({
      success: false,
      message: 'Could not load this customer. Please try again.',
    });
  }
};

exports.updateCustomer = async (req, res) => {
  try {
    const customerId = req.params.id;
    const businessId = req.staff?.businessId;
    const existing = await Customer.findById(customerId);
    if (!existing) {
      return res.status(404).json({ success: false, message: 'Customer not found.' });
    }

    if (businessId && existing.businessId && existing.businessId.toString() !== businessId.toString()) {
      return res.status(404).json({ success: false, message: 'Customer not found.' });
    }

    if (!isPrivilegedUser(req)) {
      const staffId = req.staff?._id;
      const visible = existing.visibleToStaffIds;
      const isAllowed =
        Array.isArray(visible) &&
        visible.length > 0 &&
        (staffId && visible.some((id) => id?.toString?.() === staffId.toString()));

      if (!isAllowed) {
        return res.status(404).json({ success: false, message: 'Customer not found.' });
      }
    }

    const updatePayload = { ...req.body };
    if (updatePayload.customerNumber != null && String(updatePayload.customerNumber).trim() !== '') {
      updatePayload.customerNumber = normalizeCustomerNumber(updatePayload.customerNumber);
    }
    if (updatePayload.emailId != null && String(updatePayload.emailId).trim() !== '') {
      updatePayload.emailId = normalizeEmailId(updatePayload.emailId);
    }
    const nextPhone =
      updatePayload.customerNumber !== undefined
        ? updatePayload.customerNumber
        : existing.customerNumber;
    const nextEmail =
      updatePayload.emailId !== undefined ? updatePayload.emailId : existing.emailId;

    const duplicate = await findDuplicateCustomerConflict({
      businessId: existing.businessId,
      customerNumber: nextPhone,
      emailId: nextEmail,
      excludeCustomerId: customerId,
    });
    if (duplicate) {
      return res.status(409).json({ success: false, message: duplicate.message });
    }

    const customer = await Customer.findByIdAndUpdate(customerId, updatePayload, {
      new: true,
      runValidators: true,
    }).lean();
    res.status(200).json(customer);
  } catch (error) {
    console.error('[Customers] Error updating customer:', error);
    const mapped = customerSaveErrorResponse(error);
    if (mapped) {
      return res.status(mapped.status).json(mapped.body);
    }
    res.status(500).json({
      success: false,
      message: 'Could not update customer. Please try again.',
    });
  }
};