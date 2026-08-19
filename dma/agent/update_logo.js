const fs = require('fs');
const path = require('path');

const imgPath = path.join(__dirname, '../admin_console/public/ektaHr_logo_cropped.png');
const base64Data = fs.readFileSync(imgPath).toString('base64');

const csPath = path.join(__dirname, 'AgentSingle.cs');
let csContent = fs.readFileSync(csPath, 'utf8');

const regex = /public const string LOGO_BASE64_DATA = ".*?";/s;
csContent = csContent.replace(regex, `public const string LOGO_BASE64_DATA = "${base64Data}";`);

fs.writeFileSync(csPath, csContent);
console.log('Successfully updated LOGO_BASE64_DATA in AgentSingle.cs! Length: ' + base64Data.length);
