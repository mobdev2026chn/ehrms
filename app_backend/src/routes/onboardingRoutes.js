const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { protect } = require('../middleware/authMiddleware');
const { getMyOnboarding, getAllOnboardings, uploadDocument, createCustomer } = require('../controllers/onboardingController');

// Configure multer for file uploads
const uploadsDir = path.join(__dirname, '../../uploads');
const onboardingDir = path.join(uploadsDir, 'onboarding');

// Ensure directories exist
[uploadsDir, onboardingDir].forEach(dir => {
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
    }
});

// Configure storage for onboarding documents
const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        cb(null, onboardingDir);
    },
    filename: (req, file, cb) => {
        const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
        const ext = path.extname(file.originalname);
        cb(null, `onboarding-${uniqueSuffix}${ext}`);
    }
});

// File filter for onboarding documents
const fileFilter = (req, file, cb) => {
    const allowedTypes = [
        'application/pdf',
        'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'image/jpeg',
        'image/jpg',
        'image/png'
    ];
    if (allowedTypes.includes(file.mimetype)) {
        cb(null, true);
    } else {
        cb(new Error('Invalid file type. Only PDF, DOC, DOCX, JPG, and PNG files are allowed'));
    }
};

const upload = multer({
    storage: storage,
    fileFilter: fileFilter,
    limits: {
        fileSize: 10 * 1024 * 1024 // 10MB
    }
});

router.post('/customers', createCustomer);

// Get current user's onboarding
router.get('/my-onboarding', protect, getMyOnboarding);

// Get all onboardings (admin only)
router.get('/', protect, getAllOnboardings);

// Upload document for onboarding
router.post('/:onboardingId/documents/:documentId/upload', protect, upload.single('file'), uploadDocument);

module.exports = router;
