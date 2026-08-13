const fs = require('fs');
const path = require('path');

function getAppBackendPath() {
    const candidates = [
        path.join(__dirname, '../../../../app_backend'),
        path.join(__dirname, '../../../app_backend'),
        path.join(__dirname, '../../app_backend'),
        path.resolve('d:/Projects/ektaHr/ehrms-main/ehrms-main/app_backend'),
        path.resolve('../ektaHr/ehrms-main/ehrms-main/app_backend')
    ];

    for (const candidate of candidates) {
        if (fs.existsSync(candidate)) {
            return candidate;
        }
    }

    return path.join(__dirname, '../../../../app_backend');
}

module.exports = getAppBackendPath();
