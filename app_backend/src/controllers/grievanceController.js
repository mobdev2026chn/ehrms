const mongoose = require('mongoose');
const path = require('path');
const fs = require('fs');
const Grievance = require('../models/Grievance');
const GrievanceCategory = require('../models/GrievanceCategory');
const GrievanceAttachment = require('../models/GrievanceAttachment');
const GrievanceNote = require('../models/GrievanceNote');
const GrievanceStatusHistory = require('../models/GrievanceStatusHistory');
const GrievanceFeedback = require('../models/GrievanceFeedback');
const GrievanceEscalationRule = require('../models/GrievanceEscalationRule');
const Staff = require('../models/Staff');
const User = require('../models/User');

const getUserName = async (userId) => {
    try {
        const user = await User.findById(userId).select('name').lean();
        return user?.name || 'Unknown';
    } catch (err) {
        console.error('Error fetching user name:', err);
        return 'Unknown';
    }
};

const calculateSLADueDate = (slaDays, createdAt) => {
    const dueDate = new Date(createdAt);
    dueDate.setDate(dueDate.getDate() + slaDays);
    return dueDate;
};

const getBusinessId = (req) => req.staff?.businessId || req.user?.companyId || req.companyId;

// Get categories list (active only)
exports.getCategories = async (req, res) => {
    try {
        const businessId = getBusinessId(req);
        if (!businessId) {
            return res.status(400).json({ success: false, message: 'Business context not found' });
        }
        const query = { businessId, isActive: true };
        if (req.query.isActive === 'true' || req.query.isActive === 'false') {
            query.isActive = req.query.isActive === 'true';
        }
        const categories = await GrievanceCategory.find(query)
            .select('name description')
            .sort({ name: 1 })
            .lean();
        return res.json({ success: true, data: categories });
    } catch (err) {
        console.error('Error fetching categories:', err);
        return res.status(500).json({ success: false, message: 'Error fetching categories' });
    }
};

// Get my grievances (employee-side)
exports.getGrievances = async (req, res) => {
    try {
        const businessId = getBusinessId(req);
        if (!businessId) {
            return res.status(400).json({ success: false, message: 'Business context not found' });
        }
        const staff = await Staff.findOne({ userId: req.user._id });
        if (!staff) {
            return res.json({
                success: true,
                data: {
                    grievances: [],
                    pagination: { page: 1, limit: 20, total: 0, pages: 0 }
                }
            });
        }
        const { status, search, page = 1, limit = 20, sortBy = 'createdAt', sortOrder = 'desc' } = req.query;
        const query = { businessId, employeeId: staff._id, softDeleted: false };
        if (status && status !== 'all') query.status = status;
        if (search) {
            query.$or = [
                { ticketId: { $regex: search, $options: 'i' } },
                { title: { $regex: search, $options: 'i' } },
                { description: { $regex: search, $options: 'i' } }
            ];
        }
        const skip = (Number(page) - 1) * Number(limit);
        const sort = { [sortBy]: sortOrder === 'desc' ? -1 : 1 };
        const [grievances, total] = await Promise.all([
            Grievance.find(query)
                .populate('categoryId', 'name')
                .sort(sort)
                .skip(skip)
                .limit(Number(limit))
                .lean(),
            Grievance.countDocuments(query)
        ]);
        return res.json({
            success: true,
            data: {
                grievances,
                pagination: {
                    page: Number(page),
                    limit: Number(limit),
                    total,
                    pages: Math.ceil(total / Number(limit)) || 1
                }
            }
        });
    } catch (err) {
        console.error('Error fetching grievances:', err);
        return res.status(500).json({ success: false, message: 'Error fetching grievances' });
    }
};

// Get single grievance by ID
exports.getGrievanceById = async (req, res) => {
    try {
        const { id } = req.params;
        const businessId = getBusinessId(req);
        if (!businessId) {
            return res.status(400).json({ success: false, message: 'Business context not found' });
        }
        const staff = await Staff.findOne({ userId: req.user._id });
        if (!staff) {
            return res.status(403).json({ success: false, message: 'Staff record not found' });
        }
        const grievance = await Grievance.findOne({
            _id: id,
            businessId,
            employeeId: staff._id,
            softDeleted: false
        })
            .populate('categoryId', 'name description')
            .populate('assignedTo', 'name email')
            .lean();
        if (!grievance) {
            return res.status(404).json({ success: false, message: 'Grievance not found' });
        }
        const [attachments, notes, statusHistory, feedback] = await Promise.all([
            GrievanceAttachment.find({ grievanceId: id, isInternal: false })
                .populate('uploadedBy', 'name')
                .sort({ createdAt: -1 })
                .lean(),
            GrievanceNote.find({ grievanceId: id, noteType: 'Public' })
                .populate('createdBy', 'name')
                .sort({ createdAt: -1 })
                .lean(),
            GrievanceStatusHistory.find({ grievanceId: id })
                .populate('changedBy', 'name')
                .sort({ createdAt: -1 })
                .lean(),
            GrievanceFeedback.findOne({ grievanceId: id })
                .populate('submittedBy', 'name')
                .lean()
        ]);
        return res.json({
            success: true,
            data: {
                grievance,
                attachments,
                notes,
                statusHistory,
                feedback
            }
        });
    } catch (err) {
        console.error('Error fetching grievance:', err);
        return res.status(500).json({ success: false, message: 'Error fetching grievance' });
    }
};

// Create grievance
exports.createGrievance = async (req, res) => {
    try {
        const { categoryId, title, description, incidentDate, peopleInvolved, priority, isAnonymous } = req.body;
        if (!categoryId || !title || !description) {
            return res.status(400).json({ success: false, message: 'Category, title, and description are required' });
        }
        const businessId = getBusinessId(req);
        if (!businessId) {
            return res.status(400).json({ success: false, message: 'Business context not found' });
        }
        const staff = await Staff.findOne({ userId: req.user._id });
        if (!staff) {
            return res.status(404).json({ success: false, message: 'Staff record not found' });
        }
        const category = await GrievanceCategory.findOne({
            _id: categoryId,
            businessId,
            isActive: true
        });
        if (!category) {
            return res.status(404).json({ success: false, message: 'Category not found or inactive' });
        }
        const escalationRule = await GrievanceEscalationRule.findOne({
            businessId,
            isActive: true,
            $or: [{ categoryId }, { categoryId: null }],
            $and: [{ $or: [{ priority: priority || 'Medium' }, { priority: null }] }]
        }).sort({ categoryId: -1, priority: -1 });
        const slaDays = escalationRule?.slaDays || 7;
        const year = new Date().getFullYear();
        const businessIdObj = mongoose.Types.ObjectId.isValid(businessId) ? new mongoose.Types.ObjectId(businessId) : businessId;
        const count = await Grievance.countDocuments({
            ticketId: new RegExp(`^GRV-${year}-`),
            businessId: businessIdObj
        });
        const sequence = String(count + 1).padStart(4, '0');
        const ticketId = `GRV-${year}-${sequence}`;
        const grievance = await Grievance.create({
            ticketId,
            employeeId: staff._id,
            categoryId: category._id,
            category: category.name,
            title,
            description,
            incidentDate: incidentDate ? new Date(incidentDate) : undefined,
            peopleInvolved: Array.isArray(peopleInvolved) ? peopleInvolved : [],
            priority: priority || 'Medium',
            isAnonymous: isAnonymous === true,
            status: 'Submitted',
            businessId: businessIdObj,
            createdBy: req.user._id,
            slaDays,
            slaDueDate: calculateSLADueDate(slaDays, new Date())
        });
        const userName = await getUserName(req.user._id);
        await GrievanceStatusHistory.create({
            grievanceId: grievance._id,
            fromStatus: '',
            toStatus: 'Submitted',
            changedBy: req.user._id,
            changedByName: userName,
            reason: 'Grievance submitted'
        });
        const populated = await Grievance.findById(grievance._id)
            .populate('employeeId', 'name email employeeId department')
            .populate('categoryId', 'name')
            .lean();
        return res.status(201).json({
            success: true,
            message: 'Grievance created successfully',
            data: populated
        });
    } catch (err) {
        console.error('Error creating grievance:', err);
        return res.status(500).json({ success: false, message: 'Error creating grievance' });
    }
};

// Add note (employee can only add Public)
exports.addGrievanceNote = async (req, res) => {
    try {
        const { id } = req.params;
        const { content, noteType = 'Public' } = req.body;
        if (!content || !content.trim()) {
            return res.status(400).json({ success: false, message: 'Note content is required' });
        }
        const businessId = getBusinessId(req);
        const staff = await Staff.findOne({ userId: req.user._id });
        if (!staff) return res.status(403).json({ success: false, message: 'Staff record not found' });
        const grievance = await Grievance.findOne({
            _id: id,
            businessId,
            employeeId: staff._id,
            softDeleted: false
        });
        if (!grievance) return res.status(404).json({ success: false, message: 'Grievance not found' });
        const userName = await getUserName(req.user._id);
        const note = await GrievanceNote.create({
            grievanceId: id,
            noteType: 'Public',
            content: content.trim(),
            createdBy: req.user._id,
            createdByName: userName
        });
        const populated = await GrievanceNote.findById(note._id).populate('createdBy', 'name').lean();
        return res.status(201).json({ success: true, message: 'Note added successfully', data: populated });
    } catch (err) {
        console.error('Error adding note:', err);
        return res.status(500).json({ success: false, message: 'Error adding note' });
    }
};

// Upload attachment (employee: isInternal must be false)
exports.uploadGrievanceAttachment = async (req, res) => {
    try {
        const { id } = req.params;
        const isInternal = req.body.isInternal === true || req.body.isInternal === 'true';
        if (isInternal) {
            return res.status(403).json({ success: false, message: 'Employees cannot upload internal attachments' });
        }
        if (!req.file) {
            return res.status(400).json({ success: false, message: 'File is required' });
        }
        const businessId = getBusinessId(req);
        const staff = await Staff.findOne({ userId: req.user._id });
        if (!staff) return res.status(403).json({ success: false, message: 'Staff record not found' });
        const grievance = await Grievance.findOne({
            _id: id,
            businessId,
            employeeId: staff._id,
            softDeleted: false
        });
        if (!grievance) return res.status(404).json({ success: false, message: 'Grievance not found' });
        const ext = path.extname(req.file.originalname || '') || '.pdf';
        const filename = `grievance_${grievance.ticketId}_${Date.now()}_${Math.round(Math.random() * 1E9)}${ext}`;
        const relativePath = path.join('uploads', 'grievances', filename);
        const fullPath = path.join(process.cwd(), relativePath);
        const dir = path.dirname(fullPath);
        if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(fullPath, req.file.buffer || fs.readFileSync(req.file.path));
        if (req.file.path && fs.existsSync(req.file.path)) {
            try { fs.unlinkSync(req.file.path); } catch (e) {}
        }
        const fileUrl = `uploads/grievances/${filename}`;
        const attachment = await GrievanceAttachment.create({
            grievanceId: id,
            filename,
            originalName: req.file.originalname,
            fileUrl,
            filePath: fileUrl,
            fileType: req.file.mimetype,
            fileSize: req.file.size,
            uploadedBy: req.user._id,
            isInternal: false
        });
        const populated = await GrievanceAttachment.findById(attachment._id)
            .populate('uploadedBy', 'name')
            .lean();
        return res.status(201).json({
            success: true,
            message: 'Attachment uploaded successfully',
            data: populated
        });
    } catch (err) {
        console.error('Error uploading attachment:', err);
        return res.status(500).json({ success: false, message: 'Error uploading attachment' });
    }
};

// Submit feedback
exports.submitGrievanceFeedback = async (req, res) => {
    try {
        const { id } = req.params;
        const { rating, feedback } = req.body;
        if (!rating || !feedback) {
            return res.status(400).json({ success: false, message: 'Rating and feedback are required' });
        }
        if (rating < 1 || rating > 5) {
            return res.status(400).json({ success: false, message: 'Rating must be between 1 and 5' });
        }
        const businessId = getBusinessId(req);
        const staff = await Staff.findOne({ userId: req.user._id });
        if (!staff) return res.status(403).json({ success: false, message: 'Staff record not found' });
        const grievance = await Grievance.findOne({
            _id: id,
            businessId,
            employeeId: staff._id,
            softDeleted: false
        });
        if (!grievance) return res.status(404).json({ success: false, message: 'Grievance not found' });
        if (grievance.status !== 'Closed') {
            return res.status(400).json({ success: false, message: 'Feedback can only be submitted for closed grievances' });
        }
        const existing = await GrievanceFeedback.findOne({ grievanceId: id });
        if (existing) {
            return res.status(400).json({ success: false, message: 'Feedback already submitted for this grievance' });
        }
        const feedbackRecord = await GrievanceFeedback.create({
            grievanceId: id,
            rating,
            feedback,
            submittedBy: req.user._id
        });
        grievance.employeeRating = rating;
        grievance.employeeFeedback = feedback;
        grievance.feedbackSubmittedAt = new Date();
        await grievance.save();
        const populated = await GrievanceFeedback.findById(feedbackRecord._id)
            .populate('submittedBy', 'name')
            .lean();
        return res.status(201).json({
            success: true,
            message: 'Feedback submitted successfully',
            data: populated
        });
    } catch (err) {
        console.error('Error submitting feedback:', err);
        return res.status(500).json({ success: false, message: 'Error submitting feedback' });
    }
};
