/**
 * Form controller – form templates assigned to staff, create form responses.
 * Used by Flutter arrived screen to show/fill forms before completing task.
 */
const FormTemplate = require('../models/FormTemplate');
const FormResponse = require('../models/FormResponse');
const Task = require('../models/Task');
const Staff = require('../models/Staff');

/**
 * GET /form-templates/assigned
 * Returns form templates assigned to the authenticated staff.
 * Query: staffId (optional, defaults to req.staff._id)
 */
const getAssignedTemplates = async (req, res) => {
  try {
    const staffId = req.query.staffId || req.staff?._id;
    if (!staffId) {
      return res.status(400).json({
        success: false,
        error: { message: 'Staff ID is required' },
      });
    }

    const templates = await FormTemplate.find({
      isActive: true,
      assignedTo: staffId,
    })
      .sort({ createdAt: -1 })
      .lean();

    res.json({
      success: true,
      data: { templates },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: { message: error.message || 'Failed to fetch form templates' },
    });
  }
};

/**
 * GET /form-responses
 * Check if form response exists for task+staff+template.
 * Query: taskId, staffId, templateId (optional)
 */
const getFormResponses = async (req, res) => {
  try {
    const { taskId, staffId, templateId } = req.query;
    const query = {};

    if (taskId) query.taskId = taskId;
    if (staffId) query.staffId = staffId;
    if (templateId) query.templateId = templateId;

    const responses = await FormResponse.find(query)
      .populate('templateId', 'templateName fields')
      .lean();

    res.json({
      success: true,
      data: { responses },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: { message: error.message || 'Failed to fetch form responses' },
    });
  }
};

/**
 * POST /form-responses
 * Create form response. Body: { templateId, taskId, staffId, responses }
 */
const createFormResponse = async (req, res) => {
  try {
    const { templateId, taskId, staffId, responses } = req.body;

    if (!templateId || !taskId || !staffId || !responses || typeof responses !== 'object') {
      return res.status(400).json({
        success: false,
        error: { message: 'templateId, taskId, staffId, and responses (object) are required' },
      });
    }

    const template = await FormTemplate.findById(templateId);
    if (!template) {
      return res.status(404).json({
        success: false,
        error: { message: 'Form template not found' },
      });
    }

    const task = await Task.findById(taskId);
    if (!task) {
      return res.status(404).json({
        success: false,
        error: { message: 'Task not found' },
      });
    }

    const staff = await Staff.findById(staffId);
    if (!staff) {
      return res.status(404).json({
        success: false,
        error: { message: 'Staff not found' },
      });
    }

    const businessId = req.companyId || staff.businessId || task.businessId;
    if (!businessId) {
      return res.status(400).json({
        success: false,
        error: { message: 'Business ID is required' },
      });
    }

    const existing = await FormResponse.findOne({
      templateId,
      taskId,
      staffId,
    });
    if (existing) {
      return res.status(400).json({
        success: false,
        error: { message: 'Form already submitted for this task' },
      });
    }

    const formResponse = await FormResponse.create({
      templateId,
      taskId,
      staffId,
      responses,
      businessId,
    });

    const populated = await FormResponse.findById(formResponse._id)
      .populate('templateId', 'templateName fields')
      .populate('taskId', 'taskId taskTitle status')
      .populate('staffId', 'name employeeId email')
      .lean();

    res.status(201).json({
      success: true,
      data: { response: populated },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: { message: error.message || 'Failed to create form response' },
    });
  }
};

module.exports = {
  getAssignedTemplates,
  getFormResponses,
  createFormResponse,
};
