const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const router = express.Router();
const grievanceController = require('../controllers/grievanceController');
const { protect } = require('../middleware/authMiddleware');

const uploadsDir = path.join(process.cwd(), 'uploads');
const grievanceDir = path.join(uploadsDir, 'grievances');
[uploadsDir, grievanceDir].forEach((dir) => {
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
});

const storage = multer.memoryStorage();
const fileFilter = (req, file, cb) => {
    const allowed = [
        'application/pdf',
        'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/gif',
        'application/vnd.ms-excel',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'text/plain'
    ];
    if (allowed.includes(file.mimetype)) {
        cb(null, true);
    } else {
        cb(new Error('Invalid file type. Allowed: PDF, DOC, DOCX, Images, Excel, TXT (max 20MB)'));
    }
};
const upload = multer({
    storage,
    fileFilter,
    limits: { fileSize: 20 * 1024 * 1024 }
});

router.use(protect);

router.get('/categories/list', grievanceController.getCategories);
router.get('/', grievanceController.getGrievances);
router.get('/:id', grievanceController.getGrievanceById);
router.post('/', grievanceController.createGrievance);
router.post('/:id/notes', grievanceController.addGrievanceNote);
router.post('/:id/attachments', upload.single('file'), grievanceController.uploadGrievanceAttachment);
router.post('/:id/feedback', grievanceController.submitGrievanceFeedback);

module.exports = router;
