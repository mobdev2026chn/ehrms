const fs = require('fs');
const path = require('path');

// 1. Read ektaHr_final.png
const imgPath = path.join(__dirname, 'publish/ektaHr_final.png');
const base64Data = fs.readFileSync(imgPath).toString('base64');

// 2. Embed into AgentSingle.cs
const csPath = path.join(__dirname, 'AgentSingle.cs');
let csContent = fs.readFileSync(csPath, 'utf8');

const regex = /public const string LOGO_BASE64_DATA = ".*?";/s;
csContent = csContent.replace(regex, `public const string LOGO_BASE64_DATA = "${base64Data}";`);
fs.writeFileSync(csPath, csContent);

console.log('Successfully set ektaHr_final.png in AgentSingle.cs! Length: ' + base64Data.length);
