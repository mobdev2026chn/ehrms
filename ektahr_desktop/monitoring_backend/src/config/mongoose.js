/**
 * Single Mongoose instance shared by all monitoring_backend models and app_backend models (Staff, Company).
 * Must use this so Device/MonitoringSettings use the same connection that db.js connects.
 */
const path = require('path');
const fs = require('fs');
const appBackendRoot = require('./appBackendPath');

let mongoose;
const appBackendMongoose = path.join(appBackendRoot, 'node_modules', 'mongoose');

if (fs.existsSync(appBackendMongoose)) {
    mongoose = require(appBackendMongoose);
} else {
    mongoose = require('mongoose');
}

module.exports = mongoose;
