const path = require('path');
const fs = require('fs');
const appBackendRoot = require('./appBackendPath');
const mongoose = require('./mongoose');

const MONITORING_COLLECTIONS = [
    'monitoringversions',
    'monitoringdevices',
    'monitoringlogs',
    'monitoringscreenshots',
    'monitoringsettings',
    'monitoringdailysummaries',
    'monitoringstaffs',
    'monitoringattendancecache'
];

const ensureMonitoringCollections = async () => {
    const conn = mongoose.connection;
    const existing = await conn.db.listCollections().toArray();
    const names = new Set(existing.map(c => c.name));
    for (const name of MONITORING_COLLECTIONS) {
        if (!names.has(name)) {
            await conn.db.createCollection(name);
        }
    }
};

let listenersAttached = false;

const connectDB = async () => {
    try {
        const poolSize = parseInt(process.env.MONGODB_POOL_SIZE, 10) || 50;
        const options = {
            serverSelectionTimeoutMS: 60000,
            connectTimeoutMS: 60000,
            socketTimeoutMS: 45000,
            maxPoolSize: poolSize
        };

        console.log('[DB] Connecting Mongoose to MongoDB URI...');
        if (mongoose.connection.readyState !== 1) {
            await mongoose.connect(process.env.MONGODB_URI, options);
            console.log('[DB] Mongoose connected successfully! Host:', mongoose.connection.host);
        }

        try {
            const localMongoose = require('mongoose');
            if (localMongoose !== mongoose && localMongoose.connection.readyState !== 1) {
                await localMongoose.connect(process.env.MONGODB_URI, options);
                console.log('[DB] Local Mongoose connected successfully!');
            }
        } catch (e) {
            console.error('[DB] Error connecting localMongoose:', e.message);
        }

        try {
            const appBackendMongoosePath = path.join(appBackendRoot, 'node_modules', 'mongoose');
            if (fs.existsSync(appBackendMongoosePath)) {
                const appBackendMongoose = require(appBackendMongoosePath);
                if (appBackendMongoose !== mongoose && appBackendMongoose.connection.readyState !== 1) {
                    await appBackendMongoose.connect(process.env.MONGODB_URI, options);
                    console.log('[DB] appBackendMongoose connected successfully!');
                }
            }
        } catch (e) {
            console.error('[DB] Error connecting appBackendMongoose:', e.message);
        }

        if (!listenersAttached) {
            listenersAttached = true;
            mongoose.connection.on('error', (e) => console.error('[DB Event] Error:', e.message));
            mongoose.connection.on('disconnected', () => console.warn('[DB Event] Disconnected'));
        }

        await ensureMonitoringCollections();
    } catch (error) {
        console.error('[DB] connectDB failed:', error.message);
        throw error;
    }
};

module.exports = connectDB;
