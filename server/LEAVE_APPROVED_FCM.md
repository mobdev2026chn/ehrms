# Leave approved – FCM notification (backend)

When a **leave request is approved** (in your backend/admin), send a push notification to the employee so they see it **even when the app is closed** (system shows it in the notification tray). Use the payload below with both `notification` and `data`.

**Message:**  
`Your leave request approved for {leave type} on {date}`

## When to send

In your leave-approval API (e.g. when status changes to "approved"), after saving:

1. Resolve the **employee’s FCM token(s)** (from your `user_fcm_tokens` or similar table).
2. Call FCM (HTTP v1 or Firebase Admin SDK) with the payload below.

## FCM payload

Send a **notification message** (so the system tray shows the text) and **data** (so the app can open the right screen when the user taps).

- **Title:** `Leave Approved` (or similar)
- **Body:** `Your leave request approved for {leaveType} on {date}`  
  - Example: `Your leave request approved for Casual Leave on 15 Feb 2025`
- **Data** (optional, for tap-to-open):
  - `module` = `leave` (so the app opens My Requests → Leave tab)
  - `type` = `leave_approved`
  - `leaveType` = e.g. `Casual Leave`
  - `date` = e.g. `15 Feb 2025` or ISO date

### Example (Firebase Admin SDK – Node)

```js
await admin.messaging().send({
  token: employeeFcmToken,
  notification: {
    title: 'Leave Approved',
    body: `Your leave request approved for ${leaveType} on ${formattedDate}`,
  },
  data: {
    module: 'leave',
    type: 'leave_approved',
    leaveType: leaveType,
    date: formattedDate,
  },
  android: { priority: 'high' },
});
```

### Example (REST – FCM HTTP v1)

POST to `https://fcm.googleapis.com/v1/projects/{project_id}/messages:send`  
Body:

```json
{
  "message": {
    "token": "<employee_fcm_token>",
    "notification": {
      "title": "Leave Approved",
      "body": "Your leave request approved for Casual Leave on 15 Feb 2025"
    },
    "data": {
      "module": "leave",
      "type": "leave_approved",
      "leaveType": "Casual Leave",
      "date": "15 Feb 2025"
    },
    "android": { "priority": "high" }
  }
}
```

Use your **Firebase service account** (or OAuth 2.0 access token) for the `Authorization` header.

## App behaviour

- The **app** already handles `module: "leave"` / `"requests"`: when the user **taps** the notification, it opens **My Requests** with the **Leave** tab.
- The app sends the FCM token to your API after login and on app start (when logged in). Your backend **must** implement the endpoint below and store the token per user so you can target the right device when leave is approved.

### Backend: receive FCM token from the app

**POST** `{API_BASE_URL}/notifications/fcm-token`  
**Headers:** `Authorization: Bearer <user_access_token>`  
**Body:** `{ "fcmToken": "<device_fcm_token>" }`

- Validate the user from the access token.
- Store/update the FCM token for that user (e.g. in a `user_fcm_tokens` table or on the user/staff record). When leave is approved, look up the employee’s FCM token and send the notification as above.
- If you don’t implement this endpoint, the app will log `[FCM] sendTokenToBackend: failed` and the backend will have no token to send to when leave is approved.
