require('dotenv').config();
const mongoose = require('mongoose');
const Staff = require('../src/models/Staff');
const User = require('../src/models/User');

async function main() {
  await mongoose.connect(process.env.MONGODB_URI);
  console.log('Connected to MongoDB');

  const staffList = await Staff.find({}).select('name email employeeId avatar faceEnrollEmbeddings faceReferenceImage faceFirstImage faceEnrolledAt').lean();
  console.log(`Total staff in DB: ${staffList.length}`);

  for (const s of staffList) {
    const hasEnrollEmbeddings = Array.isArray(s.faceEnrollEmbeddings) && s.faceEnrollEmbeddings.length > 0;
    console.log(`- Staff: ${s.name || 'Unknown'} (Email: ${s.email || 'None'}, EmpID: ${s.employeeId || 'None'})`);
    console.log(`  * Enrolled Embeddings: ${hasEnrollEmbeddings ? `YES (${s.faceEnrollEmbeddings.length} samples, enrolled at ${s.faceEnrolledAt})` : 'NO'}`);
    console.log(`  * Avatar: ${s.avatar ? s.avatar : 'None'}`);
    console.log(`  * faceReferenceImage: ${s.faceReferenceImage ? s.faceReferenceImage : 'None'}`);
    console.log(`  * faceFirstImage: ${s.faceFirstImage ? s.faceFirstImage : 'None'}`);
  }

  await mongoose.disconnect();
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
