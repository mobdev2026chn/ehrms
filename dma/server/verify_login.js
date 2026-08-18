const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const uri = 'mongodb://akashaskeva_db_user:4wdqSQSYRKA76chi@ac-r6pxte7-shard-00-00.wgu7miq.mongodb.net:27017,ac-r6pxte7-shard-00-01.wgu7miq.mongodb.net:27017,ac-r6pxte7-shard-00-02.wgu7miq.mongodb.net:27017/DEV_HRMS?ssl=true&replicaSet=atlas-2gnfgy-shard-0&authSource=admin&appName=ekta';

async function verify() {
  await mongoose.connect(uri);
  const targetDb = mongoose.connection.useDb('DEV_HRMS');
  const admin = await targetDb.collection('admins').findOne({ email: 'sugangeniebox@gmail.com' });
  const isMatch = bcrypt.compareSync('Sugan@123', admin.password);
  console.log('LOGIN VERIFICATION FOR sugangeniebox@gmail.com / Sugan@123:', isMatch ? 'SUCCESS!' : 'FAILED!');
  await mongoose.disconnect();
}

verify();
