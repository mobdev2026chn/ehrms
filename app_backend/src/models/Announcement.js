const mongoose = require('mongoose');

const announcementSchema = new mongoose.Schema({
    title: { type: String, required: true, trim: true },
    subject: { type: String, default: '' },
    fromName: { type: String, default: '' },
    coverImage: { type: String, default: '' },
    description: { type: String, default: '', trim: true },
    /** Web: when the announcement is published. App fallback: effectiveDate. */
    publishDate: { type: Date },
    /** Web: when the announcement expires. */
    expiryDate: { type: Date },
    /** Legacy app: when the announcement is effective. */
    effectiveDate: { type: Date },
    /** Legacy app: optional end date. */
    endDate: { type: Date },
    /** Web: "all" | "specific". When "specific", only staff in targetStaffIds see it. */
    audienceType: { type: String, default: 'all' },
    /** Web: staff IDs when audienceType === "specific". */
    targetStaffIds: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Staff' }],
    /** Legacy app: if empty/missing = all employees; else only those staff. */
    assignedTo: { type: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Staff' }], default: [] },
    businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', required: true },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'Staff' },
    /** Web: "published". Legacy: "Active". */
    status: { type: String, default: 'Active' },
    attachments: { type: Array, default: [] },
    subsections: { type: Array, default: [] },
    /** App push: set once an FCM announcement push has been sent to the audience (prevents re-sending each poll tick). */
    fcmNotificationSentAt: { type: Date },
}, { timestamps: true });

module.exports = mongoose.model('Announcement', announcementSchema);
