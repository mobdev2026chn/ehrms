#!/usr/bin/env node
/**
 * Generates an RSA key pair for monitoring_backend.
 * - Private key: add to .env as RSA_PRIVATE_KEY (Worker + API use it).
 * - Public key is derived by the API from the same private key and sent to the agent.
 *
 * Run: node scripts/generate-rsa-key.js
 * Then add the printed RSA_PRIVATE_KEY value to monitoring_backend/.env and restart API + Worker.
 */

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const { privateKey } = crypto.generateKeyPairSync('rsa', {
    modulusLength: 2048,
    publicKeyEncoding: { type: 'spki', format: 'pem' },
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' }
});

// Single-line form for .env (newlines as \n)
const oneLine = privateKey
    .replace(/\r/g, '')
    .trim()
    .split('\n')
    .join('\\n');

const envPath = path.join(__dirname, '..', '.env');
console.log('Add the following line to', envPath, '(or paste the key into RSA_PRIVATE_KEY=):\n');
console.log('RSA_PRIVATE_KEY="' + oneLine + '"\n');
console.log('Then restart the API (npm run start) and Worker (npm run worker).');
if (process.argv.includes('--write-pem')) {
    const pemPath = path.join(__dirname, '..', 'monitoring_rsa_private.pem');
    fs.writeFileSync(pemPath, privateKey, 'utf8');
    console.log('Wrote', pemPath);
}
