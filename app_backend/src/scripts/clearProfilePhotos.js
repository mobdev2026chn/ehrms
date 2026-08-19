/**
 * Clear every user's profile photo (avatar) — one-time reset so the new face
 * ENROLLMENT selfie becomes the profile photo going forward.
 *
 * SAFETY:
 *   - DRY RUN by default: prints how many records WOULD change, writes nothing.
 *     Pass --apply to actually clear.
 *   - REVERSIBLE: the current avatar is copied to `avatarBackup` (first backup is
 *     preserved if the script is run twice) before `avatar` is set to null.
 *
 * Usage:
 *   node src/scripts/clearProfilePhotos.js           # dry run (safe)
 *   node src/scripts/clearProfilePhotos.js --apply    # actually clear
 *   node src/scripts/clearProfilePhotos.js --restore   # undo: avatarBackup -> avatar
 */
require('dotenv').config({ path: require('path').join(__dirname, '../../.env') });
const mongoose = require('mongoose');

const APPLY = process.argv.includes('--apply');
const RESTORE = process.argv.includes('--restore');
// The app's real data lives in `hrms-development` (the deployed dev backend), but the
// .env URI has no DB name so it defaults to `test`. Target the right DB explicitly;
// override with `--db <name>` if needed.
const dbArgIdx = process.argv.indexOf('--db');
const TARGET_DB = dbArgIdx >= 0 ? process.argv[dbArgIdx + 1] : 'hrms-development';

async function run() {
    await mongoose.connect(process.env.MONGODB_URI);
    const db = mongoose.connection.useDb(TARGET_DB, { useCache: true });
    console.log('Target DB:', TARGET_DB);

    // Operate on the raw collections so this works across databases regardless of
    // which connection the Mongoose models are bound to.
    const targets = [['Staff', db.collection('staffs')], ['User', db.collection('users')]];

    if (RESTORE) {
        console.log('=== RESTORE: avatarBackup -> avatar ===');
        for (const [name, coll] of targets) {
            const filter = { avatarBackup: { $type: 'string', $ne: '' } };
            const count = await coll.countDocuments(filter);
            console.log(`${name}: ${count} record(s) have a backup to restore`);
            if (APPLY && count > 0) {
                const res = await coll.updateMany(filter, [
                    { $set: { avatar: '$avatarBackup' } },
                ]);
                console.log(`  -> restored ${res.modifiedCount}`);
            }
        }
        await mongoose.connection.close();
        console.log(APPLY ? 'Restore complete.' : 'DRY RUN (pass --apply with --restore to execute).');
        return;
    }

    console.log(APPLY
        ? '*** APPLY MODE — profile photos WILL be cleared (backed up to avatarBackup) ***'
        : '--- DRY RUN (no changes). Add --apply to execute. ---');

    const filter = { avatar: { $type: 'string', $ne: '' } };
    for (const [name, coll] of targets) {
        const count = await coll.countDocuments(filter);
        console.log(`${name}: ${count} record(s) currently have a profile photo`);
        if (APPLY && count > 0) {
            const res = await coll.updateMany(filter, [
                { $set: { avatarBackup: { $ifNull: ['$avatarBackup', '$avatar'] }, avatar: null } },
            ]);
            console.log(`  -> cleared ${res.modifiedCount} (originals saved to avatarBackup)`);
        }
    }

    await mongoose.connection.close();
    console.log(APPLY ? 'Done — profile photos cleared.' : 'DRY RUN complete. Re-run with --apply to clear.');
}

run().catch(async (e) => {
    console.error('Error:', e.message);
    try { await mongoose.connection.close(); } catch (_) {}
    process.exit(1);
});
