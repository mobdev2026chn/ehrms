const Customer = require('../models/Customer');

function isPrivilegedUser(req) {
  // HR/Admin/Super Admin should see all customers.
  // Employees must be restricted by `visibleToStaffIds`.
  return Boolean(req.user?.role && req.user.role !== 'Employee');
}

function buildVisibleToStaffOrAllQuery({ staffId }) {
  // visibleToStaffIds absent/empty => visible to all staff
  // visibleToStaffIds includes staffId => visible to that staff
  return {
    $or: [
      { visibleToStaffIds: { $exists: false } },
      { visibleToStaffIds: { $size: 0 } },
      { visibleToStaffIds: { $in: [staffId] } },
    ],
  };
}

exports.createCustomer = async (req, res) => {
  try {
    const businessId = req.staff?.businessId;
    const addedBy = req.staff?._id || req.user?._id;
    if (!businessId) {
      return res.status(400).json({ success: false, error: 'Business context required' });
    }
    const creatorStaffId = req.staff?._id;
    const privileged = isPrivilegedUser(req);

    let visibleToStaffIdsToSet = undefined;
    if (privileged) {
      // Default for privileged users: empty => visible to all staff.
      if (Array.isArray(req.body.visibleToStaffIds)) {
        visibleToStaffIdsToSet = req.body.visibleToStaffIds;
      } else {
        visibleToStaffIdsToSet = [];
      }
    } else {
      const provided = Array.isArray(req.body.visibleToStaffIds) ? req.body.visibleToStaffIds : [];
      const creatorStr = creatorStaffId?.toString();
      const providedList = provided.filter(Boolean);
      const hasCreator = creatorStr
        ? providedList.some((id) => id?.toString?.() === creatorStr)
        : false;

      if (!creatorStr) {
        // No staff context: safest is to show nothing to employees.
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
    const newCustomer = new Customer(payload);
    await newCustomer.save();
    res.status(201).json(newCustomer.toObject ? newCustomer.toObject() : newCustomer);
  } catch (error) {
    console.error('Error creating customer:', error);
    res.status(500).json({ success: false, error: 'Server Error' });
  }
};

exports.getAllCustomers = async (req, res) => {
  try {
    const businessId = req.staff?.businessId;
    if (!businessId) {
      console.log('[Customers] GET /customers - no businessId on staff, returning empty');
      return res.status(200).json([]);
    }

    const privileged = isPrivilegedUser(req);
    const staffId = req.staff?._id;

    const filter = privileged
      ? { businessId }
      : {
          businessId,
          ...buildVisibleToStaffOrAllQuery({ staffId }),
        };

    console.log('[Customers] GET /customers - fetching with filter:', {
      businessId: businessId.toString(),
      privileged,
    });

    const customers = await Customer.find(filter).sort({ customerName: 1 }).lean();
    console.log('[Customers] Fetched', customers.length, 'customer(s)');
    res.status(200).json(customers);
  } catch (error) {
    console.error('[Customers] Error fetching customers:', error);
    res.status(500).json({ success: false, error: 'Server Error' });
  }
};

exports.getCustomerById = async (req, res) => {
  try {
    const customerId = req.params.id;
    const businessId = req.staff?.businessId;

    if (!businessId) {
      return res.status(404).json({ success: false, error: 'Customer not found' });
    }

    const privileged = isPrivilegedUser(req);
    const staffId = req.staff?._id;

    const filter = privileged
      ? { _id: customerId, businessId }
      : {
          _id: customerId,
          businessId,
          ...buildVisibleToStaffOrAllQuery({ staffId }),
        };

    console.log('[Customers] GET /customers/:id - customerId:', customerId);
    const customer = await Customer.findOne(filter).lean();
    if (!customer) {
      console.log('[Customers] Customer not found:', customerId);
      return res.status(404).json({ success: false, error: 'Customer not found' });
    }

    console.log('[Customers] Fetched customer:', customer.customerName || customerId);
    res.status(200).json(customer);
  } catch (error) {
    console.error('[Customers] Error fetching customer by ID:', error);
    res.status(500).json({ success: false, error: 'Server Error' });
  }
};

exports.updateCustomer = async (req, res) => {
  try {
    const customerId = req.params.id;
    const businessId = req.staff?.businessId;
    const existing = await Customer.findById(customerId);
    if (!existing) {
      return res.status(404).json({ success: false, error: 'Customer not found' });
    }

    if (businessId && existing.businessId && existing.businessId.toString() !== businessId.toString()) {
      return res.status(404).json({ success: false, error: 'Customer not found' });
    }

    if (!isPrivilegedUser(req)) {
      const staffId = req.staff?._id;
      const visible = existing.visibleToStaffIds;
      const isAllowed =
        !visible ||
        (Array.isArray(visible) && visible.length === 0) ||
        (staffId && visible.some((id) => id?.toString?.() === staffId.toString()));

      if (!isAllowed) {
        return res.status(404).json({ success: false, error: 'Customer not found' });
      }
    }

    const customer = await Customer.findByIdAndUpdate(customerId, req.body, {
      new: true,
      runValidators: true,
    }).lean();
    res.status(200).json(customer);
  } catch (error) {
    console.error('[Customers] Error updating customer:', error);
    res.status(500).json({ success: false, error: 'Server Error' });
  }
};