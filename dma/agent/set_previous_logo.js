const fs = require('fs');
const path = require('path');

// 1. Embed user_ekta_logo.png into AgentSingle.cs
const imgPath = path.join(__dirname, '../admin_console/public/user_ekta_logo.png');
const base64Data = fs.readFileSync(imgPath).toString('base64');

const csPath = path.join(__dirname, 'AgentSingle.cs');
let csContent = fs.readFileSync(csPath, 'utf8');

const regex = /public const string LOGO_BASE64_DATA = ".*?";/s;
csContent = csContent.replace(regex, `public const string LOGO_BASE64_DATA = "${base64Data}";`);
fs.writeFileSync(csPath, csContent);
console.log('Successfully set user_ekta_logo.png in AgentSingle.cs! Length: ' + base64Data.length);
