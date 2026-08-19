# Monitoring data – what is stored in each DB collection

All data is stored in the **same HRMS MongoDB** (database from `MONGODB_URI` in `.env`). Collections use the `monitoring*` prefix for clarity.

---

## 1. **monitoringdevices** (Device model)

**When:** On device **register** and on every **heartbeat** (and when heartbeat-offline cron runs).

| Field          | Type     | Description |
|----------------|----------|-------------|
| deviceId       | String   | Unique device hash (from machine + CPU + motherboard). |
| employeeId     | String   | Staff employee ID (e.g. EKA00001). |
| staffId        | ObjectId | Ref to `Staff` (_id). |
| tenantId       | ObjectId | Ref to `Company` (_id). |
| machineName    | String   | PC name (e.g. SURENDAR). |
| osVersion      | String   | e.g. Microsoft Windows NT 10.0.26300.0. |
| agentVersion   | String   | e.g. 1.0.0. |
| lastSeenAt     | Date     | Last heartbeat time. |
| isActive       | Boolean  | true = recently sent heartbeat; false = marked offline by cron. |
| status         | String   | `"active"` = using software; `"inactive"` = no heartbeat 10+ min. |
| consentAt      | Date     | When user accepted consent. |
| createdAt      | Date     | When document was created. |
| updatedAt      | Date     | When document was last updated. |

---

## 2. **monitoringlogs** (ActivityLog model)

**When:** Worker processes an **activity** job from the queue (about every **60 seconds** per device).

| Field          | Type     | Description |
|----------------|----------|-------------|
| tenantId       | ObjectId | Ref to Company. |
| deviceId       | String   | Device hash. |
| employeeId     | String   | Staff employee ID. |
| timestamp      | Date     | Snapshot time (UTC). |
| keystrokes     | Number   | Keystroke count in that minute. |
| mouseClicks    | Number   | Mouse click count. |
| scrollCount    | Number   | Scroll count. |
| activeWindow   | Object   | `{ processName, windowTitle, durationSeconds }` – last active window in that minute. |
| idleSeconds    | Number   | Idle time in that minute. |
| createdAt      | Date     | When document was created. |
| updatedAt      | Date     | When document was last updated. |

---

## 3. **monitoringscreenshots** (Screenshot model)

**When:** Worker processes a **screenshot** job (image uploaded to **Cloudinary**; only **metadata** is stored here).

| Field             | Type   | Description |
|-------------------|--------|-------------|
| tenantId          | ObjectId | Ref to Company. |
| employeeId        | String   | Staff employee ID. |
| deviceId          | String   | Device hash. |
| timestamp         | Date     | When screenshot was taken. |
| cloudinaryPublicId| String   | Cloudinary asset ID. |
| cloudinaryUrl     | String   | Cloudinary URL. |
| secureUrl         | String   | HTTPS URL. |
| width             | Number   | Image width. |
| height            | Number   | Image height. |
| size              | Number   | File size (bytes). |
| createdAt         | Date     | When document was created. |
| updatedAt         | Date     | When document was last updated. |

*(Actual image files are in **Cloudinary**; this collection only stores metadata and URLs.)*

---

## 4. **monitoringscores** (ProductivityScore model)

**When:** Worker creates one per **activity** insert (same job that writes to **monitoringlogs**).

| Field        | Type     | Description |
|-------------|----------|-------------|
| tenantId    | ObjectId | Ref to Company. |
| employeeId  | String   | Staff employee ID. |
| activityLogId | ObjectId | Ref to the ActivityLog for this snapshot. |
| timestamp   | Date     | Same as activity snapshot time. |
| score       | Number   | `(keystrokeWeight×keystrokes) + (mouseWeight×mouseClicks) + (idleWeight×idleSeconds)`. |
| keystrokes  | Number   | From activity. |
| mouseClicks | Number   | From activity. |
| idleSeconds | Number   | From activity. |
| createdAt   | Date     | When document was created. |
| updatedAt   | Date     | When document was last updated. |

---

## 5. **monitoringsettings** (TenantSettings model)

**When:** Created/updated by **admin** (or manually). Not auto-created by the agent; used for **per-tenant config**.

| Field                     | Type   | Description |
|---------------------------|--------|-------------|
| tenantId                  | ObjectId | Ref to Company (unique). |
| activityRetentionDays     | Number   | e.g. 90 – how long to keep monitoringlogs. |
| screenshotRetentionDays   | Number   | e.g. 30 – how long to keep monitoringscreenshots. |
| screenshotFrequencyMinutes| Number   | e.g. 5 – how often agent takes screenshots. |
| keystrokeWeight           | Number   | e.g. 0.1 – for productivity score. |
| mouseWeight               | Number   | e.g. 0.5. |
| idleWeight                | Number   | e.g. -0.02. |
| blurRules                 | Array    | `[{ processName: String }]` – which apps to blur. |
| createdAt                 | Date     | When document was created. |
| updatedAt                 | Date     | When document was last updated. |

---

## Summary

| Collection            | Written by        | When |
|-----------------------|------------------|------|
| **monitoringdevices** | API + cron       | Register, heartbeat, heartbeat-offline. |
| **monitoringlogs**    | Worker           | Every ~60 s per active device. |
| **monitoringscores**  | Worker           | With each activity log. |
| **monitoringscreenshots** | Worker      | Every N minutes per device (after Cloudinary upload). |
| **monitoringsettings**| Admin / manual   | Per-tenant monitoring config. |

All documents include **tenantId** for multi-tenant filtering. The **actual screenshot image files** are in **Cloudinary**; only metadata and URLs are in **monitoringscreenshots**.
