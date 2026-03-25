const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { protect } = require('../middleware/authMiddleware');
const {
  getAllTasks,
  getTasksByStaffId,
  getTaskById,
  createTask,
  updateTask,
  updateLocation,
  updateSteps,
  getTrackingPath,
  getCompletionReport,
  endTask,
  uploadPhotoProof,
  uploadTaskSelfie,
  sendOtp,
  verifyOtp,
} = require('../controllers/taskController');

const uploadsDir = path.join(__dirname, '../../uploads');
const taskPhotosDir = path.join(uploadsDir, 'task-photos');
[uploadsDir, taskPhotosDir].forEach((dir) => {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
});

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, taskPhotosDir),
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname) || '.jpg';
    cb(null, `task-photo-${Date.now()}-${Math.round(Math.random() * 1e9)}${ext}`);
  },
});
const upload = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    const ok = ['image/jpeg', 'image/jpg', 'image/png'].includes(file.mimetype);
    cb(ok ? null : new Error('Only JPG/PNG images allowed'), ok);
  },
});

router.get('/', getAllTasks);
router.get('/staff/:staffId', getTasksByStaffId);
router.get('/:id/completion-report', getCompletionReport);
router.get('/:id/tracking-path', protect, getTrackingPath);
router.get('/:id', getTaskById);
router.post('/', protect, createTask);
router.patch('/:id', protect, updateTask);
// Live tracking & step progress (authenticated).
router.post('/:id/location', protect, updateLocation);
router.patch('/:id/steps', protect, updateSteps);
router.post('/:id/photo', protect, upload.single('photo'), uploadPhotoProof);
router.post('/:id/selfie', protect, upload.single('photo'), uploadTaskSelfie);
router.post('/:id/send-otp', protect, sendOtp);
router.post('/:id/verify-otp', protect, verifyOtp);
router.post('/:id/end', protect, endTask);

module.exports = router;