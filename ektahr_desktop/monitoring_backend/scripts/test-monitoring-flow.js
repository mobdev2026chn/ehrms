/**
 * Test monitoring logs and screenshots insertion.
 * 1. Verifies backend is up and returns latest logs/screenshots
 * 2. Run with: node scripts/test-monitoring-flow.js
 * Prerequisites: Backend running (npm start), Agent running and logged in with shouldTrack=true
 */
require('dotenv').config();
const base = process.env.API_BASE_URL || 'http://localhost:9002/api';
const root = base.replace(/\/api\/?$/, '') || 'http://localhost:9002';

async function fetchJson(path) {
    const url = path.startsWith('http') ? path : `${root}${path.startsWith('/') ? path : '/' + path}`;
    const res = await fetch(url);
    if (!res.ok) throw new Error(`${res.status} ${res.statusText}: ${await res.text()}`);
    return res.json();
}

async function main() {
    console.log('[Test] Checking backend health...');
    const health = await fetchJson('/health');
    console.log('[Test] Health OK:', health);

    console.log('\n[Test] Fetching latest monitoring logs and screenshots...');
    const data = await fetchJson('/api/debug/latest-logs?limit=5');
    console.log(`[Test] Activity logs: ${data.activityLogsCount}`);
    console.log(`[Test] Screenshots: ${data.screenshotsCount}`);
    if (data.activityLogs?.length) {
        console.log('\n[Test] Recent activity logs:');
        data.activityLogs.forEach((l, i) => {
            const ts = l.timestamp ? new Date(l.timestamp).toLocaleString() : '?';
            console.log(`  ${i + 1}. deviceId=${l.deviceId} timestamp=${ts} keys=${l.keystrokes ?? 0} clicks=${l.mouseClicks ?? 0}`);
        });
    }
    if (data.screenshots?.length) {
        console.log('\n[Test] Recent screenshots:');
        data.screenshots.forEach((s, i) => {
            const ts = s.timestamp ? new Date(s.timestamp).toLocaleString() : '?';
            console.log(`  ${i + 1}. deviceId=${s.deviceId} timestamp=${ts} hasUrl=${s.hasUrl}`);
        });
    }
    if (!data.activityLogs?.length && !data.screenshots?.length) {
        console.log('\n[Test] No data yet. Ensure:');
        console.log('  - Agent is running and logged in');
        console.log('  - Attendance status is shouldTrack=true (checked in today)');
        console.log('  - Wait ~activityUploadIntervalSeconds (e.g. 120s) for first activity');
        console.log('  - Wait ~screenshotUploadIntervalMinutes (e.g. 3 min) for first screenshot');
    }
    console.log('\n[Test] Done.');
}

main().catch(err => {
    console.error('[Test] Error:', err.message);
    process.exit(1);
});
