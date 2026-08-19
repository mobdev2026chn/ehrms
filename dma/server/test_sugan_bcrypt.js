const bcrypt = require('bcryptjs');

const hash = '$2b$12$j544ejdpPz5UCbOHMTIdHO/Mv957K7SxAwp0868.VxxvOCeb8wS4e';

const candidates = [
  'Sugan@123', 'sugan@123', 'Sugan123', 'sugan123',
  'Geniebox@123', 'geniebox@123', 'Geniebox123', 'geniebox123',
  'Tamil@123', 'tamil@123', 'Tamil123', 'tamil123',
  'Admin@123', 'admin@123', 'Admin123', 'admin123',
  'User@123', 'user@123', 'User123', 'user123',
  'Ekta@123', 'ekta@123', 'Ekta123', 'ekta123',
  'Askeva@123', 'askeva@123', 'Askeva123', 'askeva123',
  '123456', 'password', '12345678', 'sugangeniebox@123',
  'SuganGeniebox@123', 'sugangeniebox', 'SuganGeniebox'
];

for (const cand of candidates) {
  if (bcrypt.compareSync(cand, hash)) {
    console.log('\n>>> MATCH FOUND! PASSWORD IS:', cand);
    process.exit(0);
  }
}

console.log('No direct match in common list.');
