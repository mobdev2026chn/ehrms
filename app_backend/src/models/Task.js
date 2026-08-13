const mongoose = require('mongoose');

/**
 * Tasks collection – minimal fields only.
 * taskId = TASK-XXXXXXXX-XXXX (human-readable); _id = MongoDB ObjectId.
 * task_details.taskId and trackings.taskId both store tasks._id (ObjectId).
 * Full task details are in task_details; location history is in trackings.
 */
const taskSchema = new mongoose.Schema({
  taskId: { type: String, required: true, unique: true }, // TASK-XXXXXXXX-XXXX
  taskTitle: { type: String, required: true },
  description: { type: String, default: '' },
  status: {
    type: String,
    enum: [
      'Not yet Started', 'Pending', 'In progress', 'Serving Today', 'Delayed Tasks', 'Completed Tasks', 'Reopened', 'Rejected', 'Hold', 'exited',
      'assigned', 'approved', 'staffapproved', 'pending', 'scheduled', 'in_progress', 'arrived', 'completed', 'rejected', 'reopened', 'waiting_for_approval',
      'exitOnArrival', 'exitedOnArrival', 'holdOnArrival', 'reopenedOnArrival',
    ],
    default: 'assigned',
  },
  assignedTo: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff', required: true },
  customerId: { type: mongoose.Schema.Types.ObjectId, ref: 'Customer', required: true },
  assignedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff' },
  assignedDate: { type: Date },
  expectedCompletionDate: { type: Date, required: true },
  earliestCompletionDate: { type: Date },
  latestCompletionDate: { type: Date },
  businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company' },
  source: { type: String, default: 'app' },
  // Latest exit info: status 'hold' = staff can resume; 'exited' = only after admin reopens
  task_exit: {
    status: { type: String, enum: ['hold', 'exited'], default: null },
    exitReason: { type: String, default: '' },
    exitedAt: { type: Date, default: null },
  },
  // Full history: never deleted; append on each exit/restart
  exit: { type: Array, default: [] },
  restarted: { type: Array, default: [] },
}, { timestamps: true, strict: true });

// Ensure taskId is always TASK-XXXXXXXX-XXXX format on create; fix ObjectId-like values
taskSchema.pre('save', function () {
  if (this.isNew && this.taskId) {
    const looksLikeObjectId = /^[a-fA-F0-9]{24}$/.test(String(this.taskId));
    if (looksLikeObjectId) {
      const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      const rand = () => chars[Math.floor(Math.random() * chars.length)];
      this.taskId = `TASK-${Array(8).fill(0).map(() => rand()).join('')}-${Array(4).fill(0).map(() => rand()).join('')}`;
    }
  }
});

module.exports = mongoose.model('Task', taskSchema);
