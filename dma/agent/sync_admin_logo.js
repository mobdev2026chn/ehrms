const fs = require('fs');
const path = require('path');

const src1 = path.join(__dirname, 'publish/ektaHr_final.png');
const publicDir = path.join(__dirname, '../admin_console/public');

if (fs.existsSync(src1)) {
  fs.copyFileSync(src1, path.join(publicDir, 'ektaHr_final.png'));
  console.log('Copied ektaHr_final.png to admin_console/public!');
}
