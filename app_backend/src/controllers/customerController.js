const Customer = require('../models/Customer');

exports.createCustomer = async (req, res) => {
  try {
    const businessId = req.staff?.businessId;
    const addedBy = req.staff?._id || req.user?._id;
    if (!businessId) {
      return res.status(400).json({ success: false, error: 'Business context required' });
    }
    const payload = { ...req.body, businessId, addedBy: addedBy || req.body.addedBy, source: 'app' };
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
    console.log('[Customers] GET /customers - fetching for businessId:', businessId.toString());
    const customers = await Customer.find({ businessId }).sort({ customerName: 1 }).lean();
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
    console.log('[Customers] GET /customers/:id - customerId:', customerId);
    const customer = await Customer.findById(customerId).lean();
    if (!customer) {
      console.log('[Customers] Customer not found:', customerId);
      return res.status(404).json({ success: false, error: 'Customer not found' });
    }
    if (businessId && customer.businessId && customer.businessId.toString() !== businessId.toString()) {
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