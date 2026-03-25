const Onboarding = require('../models/Onboarding');
const Staff = require('../models/Staff');
const Candidate = require('../models/Candidate');
const JobOpening = require('../models/JobOpening');
const DocumentRequirement = require('../models/DocumentRequirement');
const mongoose = require('mongoose');
const cloudinary = require('cloudinary').v2;
const fs = require('fs');
const digitalOceanService = require('../services/digitalOceanService');

// Configure Cloudinary
cloudinary.config({
    cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
    api_key: process.env.CLOUDINARY_API_KEY,
    api_secret: process.env.CLOUDINARY_API_SECRET
});

// Helper function to get document requirements for business
const getDocumentRequirementsForBusiness = async (businessId) => {
    const businessIdObj = businessId ? new mongoose.Types.ObjectId(businessId.toString()) : null;
    
    // Get business-specific requirements first, then global defaults
    const businessRequirements = await DocumentRequirement.find({
        businessId: businessIdObj,
        isActive: true
    }).sort({ order: 1 }).lean();

    const globalRequirements = await DocumentRequirement.find({
        businessId: null,
        isActive: true
    }).sort({ order: 1 }).lean();

    // Merge: business-specific override global, but include all active ones
    const requirementMap = new Map();
    
    // Add global requirements first
    globalRequirements.forEach(req => {
        requirementMap.set(req.name, req);
    });

    // Override with business-specific requirements
    businessRequirements.forEach(req => {
        requirementMap.set(req.name, req);
    });

    // If no requirements found, return default requirements matching the image
    if (requirementMap.size === 0) {
        return [
            { name: 'Personal Information Form', type: 'form', required: true, order: 1 },
            { name: 'Bank Account Details', type: 'document', required: true, order: 2 },
            { name: 'PAN Card Copy', type: 'document', required: true, order: 3 },
            { name: 'Aadhar Card Copy', type: 'document', required: true, order: 4 },
            { name: 'Educational Certificates', type: 'document', required: true, order: 5 },
            { name: 'Previous Employment Proof', type: 'document', required: false, order: 6 },
            { name: 'Address Proof', type: 'document', required: true, order: 7 },
            { name: 'Medical Certificate', type: 'document', required: false, order: 8 }
        ];
    }

    return Array.from(requirementMap.values()).sort((a, b) => (a.order || 0) - (b.order || 0));
};

// Get current user's onboarding
const getMyOnboarding = async (req, res) => {
    try {
        const userId = req.user._id;
        const staffId = req.staff?._id;

        if (!staffId) {
            return res.status(404).json({
                success: false,
                error: { message: 'Staff record not found' }
            });
        }

        // Find candidate record first to expand search options
        const staff = await Staff.findById(staffId).populate('candidateId');
        let candidate = staff?.candidateId;
        if (!candidate && staff?.email) {
            candidate = await Candidate.findOne({
                email: staff.email.toLowerCase(),
                businessId: staff.businessId
            });
        }

        // Find onboarding by staffId OR candidateId
        let query = { $or: [{ staffId }] };
        if (candidate?._id) {
            query.$or.push({ candidateId: candidate._id });
        }
        let onboarding = await Onboarding.findOne(query)
            .populate({
                path: 'staffId',
                select: 'employeeId name email phone designation department joiningDate',
                populate: {
                    path: 'userId',
                    select: 'email name'
                }
            })
            .populate({
                path: 'candidateId',
                select: 'firstName lastName email phone position jobId'
            })
            .populate('createdBy', 'email name')
            .populate('documents.reviewedBy', 'email name');

        if (!onboarding && staff) {
            // Get documents from candidate if available
            let initialDocs = [];
            if (candidate && candidate.documents && candidate.documents.length > 0) {
                initialDocs = candidate.documents.map(doc => ({
                    name: doc.name || doc.type || 'Document',
                    type: doc.type || 'document',
                    required: true,
                    status: 'COMPLETED',
                    url: doc.url,
                    uploadedAt: new Date()
                }));
            }

            // Get document requirements from database
            const requirements = await getDocumentRequirementsForBusiness(staff.businessId);

            // If candidate documents are empty, use requirements from database
            if (initialDocs.length === 0 && requirements.length > 0) {
                initialDocs = requirements.map(req => ({
                    name: req.name,
                    type: req.type,
                    required: req.required !== false, // Default to true if not specified
                    status: 'NOT_STARTED'
                }));
            }

            // Fallback to hardcoded defaults if no requirements found
            if (initialDocs.length === 0) {
                initialDocs = [
                    { name: 'Aadhar Card', type: 'document', required: true, status: 'NOT_STARTED' },
                    { name: 'PAN Card', type: 'document', required: true, status: 'NOT_STARTED' },
                    { name: 'Educational Certificates', type: 'document', required: true, status: 'NOT_STARTED' }
                ];
            }

            try {
                // Use new Onboarding() and save() instead of create() to avoid pre-save hook issues
                const newOnboarding = new Onboarding({
                    staffId: staffId,
                    candidateId: candidate?._id,
                    businessId: staff.businessId,
                    documents: initialDocs,
                    status: 'IN_PROGRESS',
                    createdBy: req.user._id
                });

                onboarding = await newOnboarding.save();

                // Re-populate for consistent response
                onboarding = await Onboarding.findById(onboarding._id)
                    .populate({
                        path: 'staffId',
                        select: 'employeeId name email phone designation department joiningDate',
                        populate: {
                            path: 'userId',
                            select: 'email name'
                        }
                    })
                    .populate({
                        path: 'candidateId',
                        select: 'firstName lastName email phone position jobId'
                    })
                    .populate('createdBy', 'email name')
                    .populate('documents.reviewedBy', 'email name');
            } catch (createErr) {
                console.error('[getMyOnboarding] Onboarding creation failed:', createErr);
                
                // Case: record was created by another process in parallel, or unique constraint violation
                onboarding = await Onboarding.findOne(query)
                    .populate({
                        path: 'staffId',
                        select: 'employeeId name email phone designation department joiningDate',
                        populate: {
                            path: 'userId',
                            select: 'email name'
                        }
                    })
                    .populate({
                        path: 'candidateId',
                        select: 'firstName lastName email phone position jobId'
                    })
                    .populate('createdBy', 'email name')
                    .populate('documents.reviewedBy', 'email name');
            }
        }


        if (!onboarding) {
            return res.status(404).json({
                success: false,
                error: { message: 'Onboarding record not found and could not be created' }
            });
        }

        // Ensure this onboarding has all required document templates.
        // This also back-fills older records that were created before
        // we started seeding default documents.
        const requirements = await getDocumentRequirementsForBusiness(onboarding.businessId);

        // Build a quick lookup of existing docs by name
        const existingByName = new Map();
        if (onboarding.documents && Array.isArray(onboarding.documents)) {
            for (const d of onboarding.documents) {
                if (d?.name) {
                    existingByName.set(d.name, d);
                }
            }
        } else {
            onboarding.documents = [];
        }

        // Add any missing required / default docs
        let needsSave = false;
        for (const req of requirements) {
            if (!existingByName.has(req.name)) {
                onboarding.documents.push({
                    name: req.name,
                    type: req.type,
                    required: req.required !== false,
                    status: 'NOT_STARTED'
                });
                needsSave = true;
            }
        }

        if (needsSave) {
            await onboarding.save();
        }

        return res.status(200).json({
            success: true,
            data: { onboarding }
        });

    } catch (error) {
        console.error('getMyOnboarding CRITICAL ERROR:', {
            message: error.message,
            stack: error.stack,
            name: error.name,
            errors: error.errors // Mongoose validation errors
        });
        res.status(500).json({
            success: false,
            error: {
                message: error.message,
                details: error.errors ? Object.keys(error.errors).map(key => error.errors[key].message) : null
            }
        });
    }
};

// Get all onboardings (admin)
const getAllOnboardings = async (req, res) => {
    try {
        const onboardings = await Onboarding.find({ businessId: req.user.businessId })
            .populate('staffId', 'employeeId name email designation department')
            .populate('candidateId', 'firstName lastName email position')
            .populate('createdBy', 'name email')
            .sort({ createdAt: -1 });

        res.json({
            success: true,
            data: { onboardings }
        });

    } catch (error) {
        console.error('getAllOnboardings Error:', error);
        res.status(500).json({
            success: false,
            error: { message: error.message }
        });
    }
};

// Upload document for onboarding
const uploadDocument = async (req, res) => {
    try {
        const { onboardingId, documentId } = req.params;
        const file = req.file;


        // Validate IDs
        if (!mongoose.Types.ObjectId.isValid(onboardingId)) {
            console.error('[uploadDocument] Invalid onboardingId:', onboardingId);
            return res.status(400).json({
                success: false,
                error: { message: `Invalid onboarding ID format: ${onboardingId}` }
            });
        }

        if (!mongoose.Types.ObjectId.isValid(documentId)) {
            console.error('[uploadDocument] Invalid documentId:', documentId);
            return res.status(400).json({
                success: false,
                error: { message: `Invalid document ID format: ${documentId}` }
            });
        }

        if (!file) {
            return res.status(400).json({
                success: false,
                error: { message: 'No file uploaded' }
            });
        }

        // Find onboarding record
        const onboarding = await Onboarding.findById(onboardingId);
        if (!onboarding) {
            console.error('[uploadDocument] Onboarding not found:', onboardingId);
            return res.status(404).json({
                success: false,
                error: { message: 'Onboarding record not found' }
            });
        }

        // Ensure current user can only upload to their own onboarding
        const staffId = req.staff?._id?.toString();
        const onboardingStaffId = onboarding.staffId?.toString();
        if (staffId && onboardingStaffId && staffId !== onboardingStaffId) {
            return res.status(403).json({
                success: false,
                error: { message: 'Not authorized to upload to this onboarding' }
            });
        }

        // Find document within onboarding
        const document = onboarding.documents.id(documentId);
        if (!document) {
            console.error('[uploadDocument] Document not found:', documentId);
            return res.status(404).json({
                success: false,
                error: { message: 'Document not found within onboarding record' }
            });
        }

        let fileUrl;
        const buffer = fs.readFileSync(file.path);
        const fileExt = (file.originalname && file.originalname.match(/\.[a-zA-Z0-9]+$/)) ? file.originalname.match(/\.[a-zA-Z0-9]+$/)[0].slice(1) : (file.mimetype && file.mimetype.includes('png') ? 'png' : file.mimetype && file.mimetype.includes('jpeg') ? 'jpg' : 'pdf');

        // Prefer Digital Ocean Spaces (HRMS folder structure: employees/{employeeName}/documents/onboarding/)
        const staff = await Staff.findById(onboarding.staffId).select('name businessId').lean();
        const companyId = staff?.businessId ? String(staff.businessId) : undefined;
        const employeeName = staff?.name || 'unknown';
        const doResult = await digitalOceanService.uploadOnboardingDocument(buffer, req, companyId, employeeName, onboardingId, documentId, fileExt);

        if (doResult.success) {
            fileUrl = doResult.url;
            if (file.path && fs.existsSync(file.path)) {
                try { fs.unlinkSync(file.path); } catch (e) { /* ignore */ }
            }
        } else {
            // Fallback to Cloudinary
            let uploadResult;
            try {
                uploadResult = await cloudinary.uploader.upload(file.path, {
                    folder: 'hrms/onboarding',
                    resource_type: 'auto',
                    public_id: `onboarding_${onboardingId}_${documentId}_${Date.now()}`,
                });
                fileUrl = uploadResult?.secure_url;
                if (file.path && fs.existsSync(file.path)) fs.unlinkSync(file.path);
            } catch (uploadError) {
                console.error('[uploadDocument] Cloudinary upload failed:', uploadError.message);
                if (file.path && fs.existsSync(file.path)) {
                    try { fs.unlinkSync(file.path); } catch (cleanupError) { /* ignore */ }
                }
                return res.status(500).json({
                    success: false,
                    error: { message: 'Failed to upload document: ' + (doResult.error || uploadError.message) }
                });
            }
            if (!fileUrl) {
                return res.status(500).json({
                    success: false,
                    error: { message: 'Failed to upload document' }
                });
            }
        }

        // Update document with uploaded URL
        document.url = fileUrl;
        document.status = 'PENDING';
        document.uploadedAt = new Date();

        await onboarding.save();


        // Re-populate for response
        const updatedOnboarding = await Onboarding.findById(onboarding._id)
            .populate({
                path: 'staffId',
                select: 'employeeId name email phone designation department joiningDate',
                populate: {
                    path: 'userId',
                    select: 'email name'
                }
            })
            .populate({
                path: 'candidateId',
                select: 'firstName lastName email phone position jobId'
            })
            .populate('createdBy', 'email name')
            .populate('documents.reviewedBy', 'email name');

        res.json({
            success: true,
            data: {
                onboarding: updatedOnboarding,
                documentUrl: fileUrl
            },
            message: 'Document uploaded successfully'
        });

    } catch (error) {
        // Clean up uploaded file on error
        if (req.file?.path && fs.existsSync(req.file.path)) {
            try {
                fs.unlinkSync(req.file.path);
            } catch (cleanupError) {
                console.error('[uploadDocument] Failed to cleanup file on error:', cleanupError.message);
            }
        }

        console.error('[uploadDocument] ❌ Error:', {
            message: error.message,
            stack: error.stack,
            name: error.name
        });

        res.status(500).json({
            success: false,
            error: { message: error.message || 'Failed to upload document' }
        });
    }
};

const Customer = require('../models/Customer'); // Import Customer model

// Create Customer
const createCustomer = async (req, res) => {
    try {
        const { customerName, customerNumber, address, emailId, city, pincode, addedBy, businessId } = req.body;

        // Set createdAt from request or default to now
        const createdAt = req.body.createdAt ? new Date(req.body.createdAt) : new Date();

        const newCustomer = new Customer({
            customerName,
            customerNumber,
            address,
            emailId,
            city,
            pincode,
            addedBy,
            businessId,
            createdAt,
            updatedAt: new Date(), // Set updatedAt as well
        });

        const customer = await newCustomer.save();
        res.status(201).json({ success: true, data: customer });
    } catch (error) {
        console.error('Error creating customer:', error);
        res.status(500).json({ success: false, error: error.message });
    }
};

module.exports = {
    getMyOnboarding,
    getAllOnboardings,
    uploadDocument,
    createCustomer,
};
