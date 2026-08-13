# Monitoring Backend Crons

## Crons Implemented

### 1. **attendance-check** (runs as separate PM2 app: `monitoring-attendance-cron`, every 1 min)
- **Script:** `src/cron/attendanceCheckCron.js`
- **Run:** `pm2 start ecosystem.config.js` (starts monitoring-attendance-cron) or `npm run attendance-check` (standalone)
- **Purpose:** 
  - Queries attendances for today's check-in/check-out per active device
  - Updates MonitoringAttendanceCache (fast lookup for agent)
  - **On checkout:** Inserts that day's productivity into `monitoringdailysummaries` for that staff

### 2. **retention** (standalone – run via OS scheduler, e.g. daily)
- **Script:** `src/cron/dataRetention.js`
- **Run:** `npm run retention`
- **Purpose:** Deletes old activity logs and screenshots per TenantSettings retention days

### 3. **heartbeat-offline** (in-code – no cron)
- **Where:** `deviceController.heartbeat` triggers `maybeMarkOfflineDevices()` (throttled to at most every 10 min)
- **Purpose:** Marks devices as offline if `lastSeenAt` exceeds 10 minutes. Driven by software heartbeats; no separate cron.

### 4. **daily-summary** (manual only)
- **Script:** `src/cron/dailySummary.js`
- **Run:** `node src/cron/dailySummary.js [YYYY-MM-DD]` (manual only)
- **Purpose:** Aggregates monitoringlogs, monitoringscores, monitoringscreenshots → monitoringdailysummaries
- **Note:** Replaced by on-checkout insert in attendanceCheckCron. Keep for manual backfill of historical dates.
