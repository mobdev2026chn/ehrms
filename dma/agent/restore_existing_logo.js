const fs = require('fs');
const path = require('path');

const imgPath = path.join(__dirname, 'publish/ektaHr_final.png');
const base64Data = fs.readFileSync(imgPath).toString('base64');

const csPath = path.join(__dirname, 'AgentSingle.cs');
let csContent = fs.readFileSync(csPath, 'utf8');

const regex = /public const string LOGO_BASE64_DATA = ".*?";/s;
csContent = csContent.replace(regex, `public const string LOGO_BASE64_DATA = "${base64Data}";`);

fs.writeFileSync(csPath, csContent);
console.log('Restored existing ektaHr_final.png logo in AgentSingle.cs! Length: ' + base64Data.length);
