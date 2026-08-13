 Complete Module Documentation

 Project-wide logic from Flutter app (`hrms`) and backend (`app_backend`)


bloc – Contains BLoC files managing state and business logic for features like auth, attendance, and tasks.
attendance – Handles attendance-related state management and logic.
auth – Manages authentication logic like login, logout, and user session.
task – Manages task-related operations and state.
config – Stores app configuration settings and constants.
core – Contains core/shared functionalities used across the app.
models – Defines data structures and models used in the app.
providers – Manages dependency injection and state providers.
repository – Handles data operations and API communication.
screens – Contains UI screens/pages of the app.
services – Includes helper services like API, storage, or background tasks.
utils – Utility/helper functions used across the app.
widgets – Reusable UI components.
main.dart – Entry point of the Flutter application.


app_backend – Main backend project handling server-side logic and APIs.
face_verify – Contains face verification/recognition related logic or models.
node_modules – Stores installed Node.js dependencies.
scripts – Contains custom scripts for automation or setup tasks.
src – Main source code for backend (routes, controllers, services).
uploads – Stores uploaded files like images or documents.
.env – Stores environment variables like API keys and DB credentials.
cron.txt – Defines scheduled background jobs or cron tasks.
customer_data.json – Sample or stored customer data in JSON format.
firebase-service-account.json – Firebase admin credentials for server integration.
index.js – Entry point of the backend server.
package-lock.json – Locks dependency versions for consistency.
package.json – Defines project metadata, scripts, and dependencies.


Dio Client (Network Layer)
DioClient – Central HTTP client used for all API requests in the app.
RetryOnRateLimitInterceptor – Automatically retries requests when server returns 429 (rate limit).
FormDataContentTypeInterceptor – Ensures correct headers for file uploads (multipart/form-data).
SessionExpiryInterceptor – Detects expired sessions (401) and clears stored user data.
setAuthToken() – Adds JWT token to request headers for authenticated APIs.
clearAuthToken() – Removes authentication token from headers.
BaseOptions – Configures base URL, timeouts, and default headers for all requests.
Interceptors – Handle retry logic, session expiry, and optional logging globally.

## 1) Architecture Overview

- **Frontend**: Flutter mobile app in `hrms`.
- **Backend**: Node.js/Express API in `app_backend`.
- **Primary domain modules**: Attendance, Breaks, Leave, Permission, Payslip, Tasks, Assets, Session/Auth.
- **Data store**: MongoDB (Mongoose models/collections).

## 2) Attendance Module - End-to-End Logic

### 2.1 Core backend files

- `app_backend/src/controllers/attendanceController.js`
- `app_backend/src/routes/attendanceRoutes.js`
- `app_backend/src/utils/leaveAttendanceHelper.js`
- `app_backend/src/utils/fineCalculationHelper.js`
- `app_backend/src/utils/resolveStaffAttendanceTemplate.js`
- `app_backend/src/models/Attendance.js`
- `app_backend/src/models/AttendanceLog.js`
- `app_backend/src/models/Staff.js`
- `app_backend/src/models/Company.js`
- `app_backend/src/models/AttendanceTemplate.js`

### 2.2 Attendance APIs

- `POST /api/attendance/checkin` -> punch in
- `PUT /api/attendance/checkout` -> punch out
- `GET /api/attendance/today` -> today status + UI allow flags
- `GET /api/attendance/month` -> month view
- `GET /api/attendance/history` -> attendance history
- `GET /api/attendance/employee/:employeeId` -> employee attendance
- `GET /api/attendance/fine-calculation` -> fine details preview/data

### 2.3 Punch-In allowed/not allowed conditions

Punch-in is blocked or allowed by these conditions:

1. **Salary required**  
   - Blocked if `staff.salary` missing or computed net monthly salary is `<= 0`.

2. **Shift assignment required**  
   - Blocked when shift is not assigned to staff.

3. **Leave conditions**
   - Full-day approved leave -> blocked.
   - Half-day leave -> controlled by helper logic (`canCheckInWithHalfDayLeave`), session, and shift/grace rules.

4. **Holiday / weekly-off policy**
   - If holiday and template disallows attendance on holidays -> blocked.
   - If weekly off and template disallows attendance on weekly off -> blocked.
   - Odd/even Saturday branch handled explicitly.

5. **Geofence validation**
   - If geofence enabled and user is outside allowed location -> blocked.

6. **Late-entry policy**
   - Flutter pre-check can block when late and `allowLateEntry` is false.
   - Backend still computes warning with policy metadata.

7. **After shift end**
   - Flutter-side pre-check blocks check-in after shift end.

### 2.4 Punch-Out conditions

1. **Attendance record must exist**
   - If no day attendance row exists -> block.

2. **Already punched out**
   - Block if already checked out (except some half-day update branches).

3. **Leave handling**
   - Full-day leave: generally blocked unless closing an open session.
   - Half-day leave: evaluated with `canCheckOutWithHalfDayLeave`.

4. **Early-exit policy**
   - Standard shift: punch-out before shift end => early minutes.
   - Open shift: early minutes from required daily hours deficit.
   - If `allowEarlyExit` false, warning generated and app may block.

5. **Geofence on checkout**
   - Enforced when template requires location checks.

### 2.5 Fine calculation logic

Main function flow:
- Attendance controller calculates late/early minutes.
- `fineCalculationHelper` computes amount based on configuration.

Sources:
- `company.settings.payroll.fineCalculation`

Rules:
1. **Late fine**
   - If punch-in within grace -> no late fine.
   - Else late minutes = `punchIn - shiftStart`.
   - Open shift days skip late fine.

2. **Early fine**
   - Standard shift: if punch-out before end -> early minutes.
   - Open shift: based on shortfall against required hours.

3. **Rule-based calculation**
   - Uses `fineRules` by `applyTo`.
   - Supports multiplier/custom/day-penalty style rule types.

4. **Fallback calculation**
   - `shiftBased`: proportional by shift hours and salary day basis.
   - `fixedPerHour`: uses configured rate or derived fallback.

Persisted fields include:
- `lateMinutes`, `earlyMinutes`, `fineHours`, `fineAmount`

## 3) Break Fine Calculation

### 3.1 Files

- `app_backend/src/controllers/breakController.js`
- `app_backend/src/routes/breakRoutes.js`
- `app_backend/src/models/Break.js`
- `app_backend/src/models/Attendance.js`

### 3.2 Break APIs

- `GET /api/breaks/current`
- `POST /api/breaks/start`
- `PATCH /api/breaks/:id/end`

### 3.3 Break fine conditions

1. Break end computes current break minutes.
2. Reads cumulative break minutes for the day.
3. Resolves shift break policy (`allowedMinutes`) and fine config.
4. If break policy disabled or allowed minutes = 0, no break fine.
5. Fine minutes = excess over cumulative allowed break.
6. Current break fine = incremental excess from previous total.
7. Fine amount computed through same fine helper and stored back to attendance.

## 4) Shift Fetching (User-based) - route, source, and collections

### 4.1 Where shift comes from

Shift context is resolved through:
- `Staff` assignment (`shiftId`, `shiftName`, attendance template links)
- Company shift definitions in:
  - `Company.settings.attendance.shifts`

### 4.2 Main shift resolution logic

- `leaveAttendanceHelper.getShiftTimings(...)`
- `resolveStaffAttendanceTemplate.loadAttendanceTemplateForStaff(...)`

These determine:
- shift type (fixed/open)
- shift start/end window
- grace minutes
- policies (late entry, early exit, permission, break)
- effective shift id

### 4.3 Collections/models involved

- `Staff` collection
- `Company` collection (business settings + shifts)
- `AttendanceTemplate` collection
- `Attendance` collection (stores applied shift snapshot/id)

## 5) Permission and Fine Calculation

### 5.1 Permission request routes

In `requestRoutes`:
- `GET /api/requests/permission`
- `GET /api/requests/permission/balance`
- `POST /api/requests/permission`
- `PATCH /api/requests/permission/:id/cancel`

### 5.2 Permission approval and fine impact

Fine engine consumes **approved permissions only**:
- attendance fine flow checks `PermissionRequest.status === 'Approved'`.
- permission minutes reduce late/early minutes before final fine amount is saved.

Tracked fields in attendance:
- `permissionApprovedMinutes`
- `permissionConsumedMinutes`
- `permissionRemainingMinutes`
- `permissionLateMinutes`
- `permissionEarlyMinutes`

Policy behavior:
- `applyTo`: late / early / both
- monthly quota enforced
- open shift: applied only in relevant branch at checkout

## 6) Permission Approval Flow

Current code has:
- employee-side create/cancel routes for permission requests.
- attendance logic expecting approved permission records.

Important implementation observation:
- Approval endpoint/controller for permission requests is not clearly present in the scanned routes in this repository snapshot.
- Therefore approval may be handled by another admin module/service not currently wired here.

## 7) Leave Request Logic (Configured Leaves Only)

### 7.1 Routes

- `GET /api/requests/leave-types/for-apply`
- `GET /api/requests/leave-balance`
- `POST /api/requests/leave/check-dates`
- `POST /api/requests/leave`
- `PATCH /api/requests/leave/:id/status`

### 7.2 Configured leave enforcement

Leave apply list is dynamically fetched from template-linked leave types:
- `staff.leaveTemplateId.leaveTypes`
- includes standard additions (`Half Day`, ensured `Unpaid Leave`)

Creation checks:
- leave type normalization and validation
- balance checks from attendance/template pool
- date conflict checks
- half-day session constraints

Result: user can apply only available/configured leave types returned by backend logic.

## 8) Payslip Request and Visibility Conditions

### 8.1 Routes

- `GET /api/requests/payslip`
- `POST /api/requests/payslip`
- `GET /api/requests/payslip/:id/view`
- `GET /api/requests/payslip/:id/download`

### 8.2 Conditions

1. Duplicate requests for same employee/month/year blocked when existing request is pending/approved.
2. View/download allowed only for status `Approved` or `Generated`.
3. Even for approved status, payslip URL must exist (generated payroll link).
4. If URL not available yet, response indicates to wait for generation.
5. Flutter UI only shows share/download action when URL exists.
6. Request dialog limits selectable months/years to valid employment period and completed months.

## 9) Attendance Detail Screen - permissions and data sources

### 9.1 Frontend files

- `hrms/lib/screens/attendance/attendance_screen.dart`
- `hrms/lib/screens/dashboard/dashboard_screen.dart`
- `hrms/lib/bloc/attendance/attendance_bloc.dart`
- `hrms/lib/services/attendance_service.dart`

### 9.2 Data source and permission display

Attendance screen pulls from:
- `/api/attendance/today`
- `/api/attendance/month`
- `/api/attendance/history`
- `/api/attendance/employee/:id`
- `/api/attendance/fine-calculation`

Fine shown in UI is sourced from attendance API response (`fineAmount` + computed details).  
`today` payload includes punch allow flags such as `checkInAllowed`, `checkOutAllowed` used for button enable/disable behavior.

## 10) Auto Logout (Inactive/Session expired/deactivated)

### 10.1 Files

- `hrms/lib/widgets/deactivation_check_wrapper.dart`
- `hrms/lib/services/auth_service.dart`
- `hrms/lib/core/network/dio_client.dart`
- `app_backend/src/routes/authRoutes.js`
- `app_backend/src/controllers/authController.js`
- `app_backend/src/middleware/authMiddleware.js`

### 10.2 Behavior

1. App-level wrapper runs periodic active checks (~5 sec).
2. Calls `/auth/check-active`.
3. If staff is deactivated -> forced logout + navigation stack clear.
4. If token/session expired (`401` with expiry messages) -> local token cleared and user redirected to login.
5. This is session-expiry/deactivation auto logout, not touch-idle timeout logic.

## 11) Assets shown in app

Declared in `hrms/pubspec.yaml`:
- `assets/images/`
- `assets/fonts/`
- `assets/ekta_logo.jpeg`

Commonly rendered:
- `assets/ekta_logo.jpeg` (splash/login)
- `assets/images/ektaHr_feature_graphic.png` (login)
- `assets/images/chat-bg.jpeg` (interaction chat background)

## 12) Tasks Module - Full Flow and Settings Logic

### 12.1 Backend routes

Mounted:
- `/api/tasks`
- `/api/tracking`

Task endpoints include create/update/status/proof/otp/end and read APIs.  
Tracking endpoints include store location, exit, restart, arrived.

### 12.2 Collections/models

- `Task`
- `TaskDetails`
- `Tracking`
- `TaskSettings`
- `FormResponse`

### 12.3 Flow

1. Create task (`POST /api/tasks`)
2. Start/mark in progress (`PATCH /api/tasks/:id`)
3. Live tracking (`POST /api/tracking/store`)
4. Exit/restart (`/api/tracking/exit`, `/api/tracking/restart`)
5. Arrive (`POST /api/tracking/arrived`)
6. Complete prerequisites:
   - photo proof
   - OTP (if enabled)
   - form submission (if assigned)
7. End task (`POST /api/tasks/:id/end`)
8. Final status:
   - `waiting_for_approval` if `requireApprovalOnComplete` enabled
   - otherwise `completed`

### 12.4 Task settings influence

Settings merged into task behavior:
- `enableOtpVerification`
- `requireApprovalOnComplete`
- `autoApprove`
- `staffWhoCanSchedule` (present in model; enforcement should be reviewed if required)

### 12.5 Permission/gating note

Current task authorization is largely token/status based.  
Some read endpoints are exposed without auth middleware in the current route file and should be security-reviewed.

## 13) Screen-by-screen module map (Flutter)

- Splash: token/session bootstrap and initial route.
- Login: authentication.
- Dashboard shell:
  - Home dashboard
  - My requests
  - Salary overview
  - Holidays
  - Attendance
  - Punch and break actions
- Requests:
  - Leave
  - Permission
  - Payslip
- Attendance:
  - Checkin/checkout flows (including selfie and geolocation conditions)
- Tasks:
  - My tasks list
  - Add task
  - Task detail
  - Live tracking
  - Arrived screen
  - OTP
  - Photo proof
  - Completion summary
  - Completed task detail/report
- Assets listing
- Performance module
- Interaction module (chat/polls)
- Announcements
- Grievance module
- Settings/profile

## 14) Required Action Items (important gaps)

1. Verify and implement/confirm **permission approval endpoint** if not present in this repo.
2. Security review for **task read routes without auth middleware**.
3. If office requires strict inactivity timeout, add explicit user-idle timer (currently session/deactivation based).
4. Confirm form route mount wiring if `/api/forms` expected by task flow.



## 15) Attendance Repository
AttendanceRepository – Acts as a bridge between BLoC and service layer for attendance operations.
checkIn() – Sends user check-in data like location, time, and optional selfie/fine details.
checkOut() – Sends user check-out data with location and optional details.
getTodayAttendance() – Fetches current day attendance data.
getAttendanceByDate() – Retrieves attendance for a specific date.
getAttendanceHistory() – Fetches paginated attendance history records.
getMonthAttendance() – Retrieves attendance data for a specific month.
clearCachesForRefresh() – Clears cached data to force fresh API calls

