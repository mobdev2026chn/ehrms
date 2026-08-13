const mongoose = require('mongoose');

const jobOpeningSchema = new mongoose.Schema({
    title: { type: String, required: true },
    jobCode: { type: String },
    department: { type: String },
    status: { type: String, default: 'Open' }
}, { timestamps: true });

module.exports = mongoose.model('JobOpening', jobOpeningSchema);
