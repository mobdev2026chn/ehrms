const fs = require('fs');
const path = require('path');

const jpegPath = path.join(__dirname, 'publish/ekta_logo.jpeg');
const jpegBytes = fs.readFileSync(jpegPath);

console.log('ekta_logo.jpeg size:', jpegBytes.length);

// Build Win32 .ico file wrapping JPEG/PNG image data
function createIcoBuffer(imgBytes) {
  const icoHeader = Buffer.alloc(6);
  icoHeader.writeUInt16LE(0, 0); // Reserved
  icoHeader.writeUInt16LE(1, 2); // Type 1 = ICO
  icoHeader.writeUInt16LE(1, 4); // 1 Image

  const dirEntry = Buffer.alloc(16);
  dirEntry.writeUInt8(0, 0);  // Width (0 = 256px)
  dirEntry.writeUInt8(0, 1);  // Height (0 = 256px)
  dirEntry.writeUInt8(0, 2);  // Colors
  dirEntry.writeUInt8(0, 3);  // Reserved
  dirEntry.writeUInt16LE(1, 4); // Planes
  dirEntry.writeUInt16LE(32, 6); // Bits per pixel
  dirEntry.writeUInt32LE(imgBytes.length, 8); // Data size
  dirEntry.writeUInt32LE(22, 12); // Data offset (6 + 16 = 22)

  return Buffer.concat([icoHeader, dirEntry, imgBytes]);
}

const icoBuffer = createIcoBuffer(jpegBytes);
const icoPath = path.join(__dirname, 'ektaHr.ico');
fs.writeFileSync(icoPath, icoBuffer);
console.log('Saved ektaHr.ico! Total size:', icoBuffer.length);

// Copy ekta_logo.jpeg to public directories & update Base64
const base64Data = jpegBytes.toString('base64');
const csPath = path.join(__dirname, 'AgentSingle.cs');
let csContent = fs.readFileSync(csPath, 'utf8');

const regex = /public const string LOGO_BASE64_DATA = ".*?";/s;
csContent = csContent.replace(regex, `public const string LOGO_BASE64_DATA = "${base64Data}";`);
fs.writeFileSync(csPath, csContent);
console.log('Updated AgentSingle.cs with ekta_logo.jpeg Base64!');

// Copy to Admin Console public
const adminPublicPath = path.join(__dirname, '../admin_console/public');
fs.writeFileSync(path.join(adminPublicPath, 'ekta_logo.jpeg'), jpegBytes);
fs.writeFileSync(path.join(adminPublicPath, 'favicon.ico'), icoBuffer);
fs.writeFileSync(path.join(adminPublicPath, 'ektaHr.ico'), icoBuffer);
console.log('Copied ekta_logo.jpeg and favicon.ico to admin_console/public!');
