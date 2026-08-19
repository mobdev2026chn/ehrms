const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const uri = 'mongodb://akashaskeva_db_user:4wdqSQSYRKA76chi@ac-r6pxte7-shard-00-00.wgu7miq.mongodb.net:27017,ac-r6pxte7-shard-00-01.wgu7miq.mongodb.net:27017,ac-r6pxte7-shard-00-02.wgu7miq.mongodb.net:27017/DEV_HRMS?ssl=true&replicaSet=atlas-2gnfgy-shard-0&authSource=admin&appName=ekta';

async function setPassword() {
  try {
    await mongoose.connect(uri);
    console.log('Connected to MongoDB DEV_HRMS');
    const targetDb = mongoose.connection.useDb('DEV_HRMS');
    const adminsCol = targetDb.collection('admins');

    const newPassword = 'Sugan@123';
    const hashedPassword = bcrypt.hashSync(newPassword, 12);

    const result = await adminsCol.updateOne(
      { email: 'sugangeniebox@gmail.com' },
      { $set: { password: hashedPassword } }
    );

    console.log('UPDATE RESULT:', result);
    console.log(`Password for sugangeniebox@gmail.com has been set to: ${newPassword}`);
    await mongoose.disconnect();
  } catch (err) {
    console.error('Error:', err);
  }
}

setPassword();
