# Publishing EktaHR to the Apple App Store

> **App:** EktaHR (`hrms`) · **Bundle ID:** `io.askeva.ektahr` · **Version:** `1.0.3` (from `pubspec.yaml`)
> Companion to [IOS_BUILD.md](IOS_BUILD.md) (building on a Mac) and the Android
> [PLAYSTORE_PUBLISHING_GUIDE.md](../PLAYSTORE_PUBLISHING_GUIDE.md).

```
A. Apple Developer account ($99/yr) ─► B. Pre-flight fixes ─► C. Build & upload (Codemagic or Mac)
   ─► D. App Store Connect listing ─► E. TestFlight test ─► F. Submit for review ─► Live
```

---

## A. Apple Developer account

1. **Apple ID:** create one at appleid.apple.com with a company email, and turn on **two-factor authentication**.
2. **Choose the enrollment type:**
   - **Organization (recommended):** the seller shows as your company name. You need a **D-U-N-S number** (free; look it up at developer.apple.com/enroll/duns-lookup, and allow up to 2 weeks), your legal entity name, a company website, and authority to sign for the company.
   - **Individual:** your personal name shows as the seller. Approval takes 1–2 days.
3. **Enroll** using the **Apple Developer** iPhone app (Account → Enroll Now) or at developer.apple.com/programs/enroll. Pay $99.
4. After approval, sign in to **appstoreconnect.apple.com** and accept the agreements under **Business**. This app is free, so you don't need the paid-apps agreement or bank details.

---

## B. Pre-flight fixes

Some of these are already done in the repo; the rest you must do yourself.

| # | Item | Status |
|---|------|--------|
| 1 | iOS app icon generated from `assets/ekta_logo.jpeg`. It was previously the default Flutter logo, which Apple rejects. | ✅ done |
| 2 | `ITSAppUsesNonExemptEncryption = NO` in `Info.plist`, so there's no export-compliance prompt on every build | ✅ done |
| 3 | App set to iPhone-only (`TARGETED_DEVICE_FAMILY = 1`), so no iPad screenshots or iPad review are needed | ✅ done |
| 4 | Background-location permission text explains the actual punch-in → punch-out tracking | ✅ done |
| 5 | **API server:** `lib/config/constants.dart` points at **UAT** (`uat.ektahr.com`). Set `baseUrl` and `webBaseUrl` to the production host for the store build. | ⚠️ you |
| 6 | **`GoogleService-Info.plist`:** without it the app opens on an init-error screen, and Apple will reject it. Firebase console → project `ehrms-929bb` → Add app → iOS → bundle `io.askeva.ektahr`. | ⚠️ you |
| 7 | **APNs key** for push notifications: developer.apple.com → Keys → + → *Apple Push Notifications service*. Download the `.p8` and upload it in Firebase → Project settings → Cloud Messaging → Apple app. | ⚠️ you |
| 8 | **Demo account** on the production server for Apple's reviewer, with face/geo restrictions relaxed so the reviewer can punch in from anywhere | ⚠️ you |
| 9 | **Privacy policy** is live at the URL in `AppConstants.privacyPolicyUrl`. Make sure it mentions camera/face images, location (including background), and chat/voice messages. | ⚠️ check |
| 10 | Bump the version in `pubspec.yaml` before each new submission, e.g. `1.0.4+15` | each release |

---

## C. Build and upload

### Option 1: Codemagic (no Mac needed; recommended from Windows)
The config is already in [`codemagic.yaml`](../../codemagic.yaml) at the repo root.

1. Sign up at **codemagic.io** with GitHub, GitLab or Bitbucket, and add this repository.
2. **App Store Connect API key:** in App Store Connect → Users and Access → **Integrations** → App Store Connect API → **+**, create a key with the **App Manager** role. Download the `.p8` and note the **Issuer ID** and **Key ID**.
3. In Codemagic → Team settings → **Integrations** → *Developer Portal* → add that key and name it exactly **`EktaHR ASC Key`**.
4. In Codemagic → Team settings → **Code signing identities** → iOS certificates → **Generate certificate** (Apple Distribution). Codemagic creates the provisioning profile automatically.
5. In Codemagic → app → **Environment variables**, add `GOOGLE_SERVICE_INFO_PLIST` in a group named **`firebase_ios`**, marked *Secure*. The value is the base64 of your plist. On Windows PowerShell:
   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("GoogleService-Info.plist")) | Set-Clipboard
   ```
6. In `codemagic.yaml`, replace `APP_STORE_APPLE_ID: "0000000000"` with the numeric **Apple ID** of the app (App Store Connect → app → App Information). Create the app first; see section D.
7. Click **Start new build** → workflow *EktaHR iOS → TestFlight*. The build takes about 20–30 minutes and lands in TestFlight automatically.

### Option 2: on a Mac
Follow [IOS_BUILD.md](IOS_BUILD.md), then run `flutter build ipa --release` and upload `build/ios/ipa/*.ipa` with the **Transporter** app.

---

## D. App Store Connect: create the app and listing

**Register the bundle ID:** developer.apple.com → Identifiers → **+** → App IDs → `io.askeva.ektahr`. Tick **Push Notifications**. Codemagic and Xcode can also do this automatically.

**New app:** App Store Connect → Apps → **+** → New App

| Field | Value |
|---|---|
| Platform | iOS |
| Name | `EktaHR`. If that name is taken, try `EktaHR - Attendance & HR`. |
| Primary language | English (U.S.) or English (India) |
| Bundle ID | `io.askeva.ektahr` |
| SKU | `ektahr-ios` |
| User access | Full access |

### Listing text (copy and paste; edit as you like)

**Subtitle** (max 30 characters)
```
Attendance, Leave & Payroll
```

**Promotional text** (max 170 characters)
```
Punch in with a selfie, apply for leave, view payslips and stay connected with your team — your company's HR, right on your iPhone.
```

**Description**
```
EktaHR is the employee app for companies that use the EktaHR HR platform. Sign in with the account your employer created for you and manage your workday from your phone.

ATTENDANCE
• Punch in and out with a selfie and location check
• Face recognition attendance
• Breaks, overtime and attendance history at a glance

FIELD WORK
• View and complete assigned field tasks
• Route and visit logging for on-duty field staff (when enabled by your employer)

LEAVE & REQUESTS
• Apply for leave, permissions and other requests
• Track approval status in real time
• Company holiday calendar

PAY & BENEFITS
• View and download payslips
• Loan and advance requests
• Asset tracking

STAY CONNECTED
• Company announcements and celebrations
• Team chat with voice messages
• Grievance submission
• Learning courses and performance reviews

FOR MANAGERS AND ADMINS
• Approve leave, attendance and requests on the go
• Staff attendance overview and live field tracking

An EktaHR company account is required. Contact your HR administrator for login details.
```

**Keywords** (max 100 characters, comma-separated)
```
hrms,attendance,payroll,leave,payslip,punch in,employee,staff,face attendance,field tracking,hr
```

| Field | Value |
|---|---|
| Category | **Business** (secondary: Productivity) |
| Support URL | e.g. `https://ektahr.com/support` (any page with contact details) |
| Marketing URL | `https://ektahr.com` (optional) |
| Privacy Policy URL | the URL in `AppConstants.privacyPolicyUrl` |
| Copyright | `2026 <Your legal company name>` |
| Price | Free |
| Availability | All countries, or just India |

### Screenshots
- **Required:** 6.9" iPhone at **1320 × 2868** (portrait), 3–10 images.
- Take them in the iPhone 16 Pro Max / 17 Pro Max simulator on a Mac, or on a real Pro Max phone. Codemagic can't take them.
- Suggested screens: Dashboard → Punch-in (selfie) → Attendance history → Leave request → Payslip → Announcements/Chat.
- Use demo data only, with no real employee names or salaries.

### App Privacy (the "nutrition label")
Go to App Store Connect → app → **App Privacy** → Get Started. Answer **Yes, we collect data**, and for every type below choose: *Used for:* **App Functionality** · *Linked to user:* **Yes** · *Used for tracking:* **No**.

| Category | Data types to tick |
|---|---|
| Contact Info | Name, Email Address, Phone Number |
| Financial Info | Other Financial Info (salary, loans) |
| Location | Precise Location |
| User Content | Photos or Videos (attendance selfies / face), Audio Data (voice messages), Other User Content (chat, grievances, requests) |
| Identifiers | User ID, Device ID |
| Sensitive Info | Leave it unticked unless you store religion, health or similar. If you do, add it. |

**Tracking:** No. The app does not track users across other companies' apps or websites for advertising.

### Age rating
Answer the questionnaire **None/No** for everything. If it asks about **user-generated content or messaging**, answer **Yes** (team chat). The result should still be **4+** or **9+**.

---

## E. TestFlight

1. Once the build finishes processing (App Store Connect → TestFlight), answer the encryption question if it appears (it won't, because the plist flag is set).
2. **Internal Testing** → **+** group → add team members. They install the **TestFlight** app and accept the invite.
3. Test the full flow on a **real iPhone**: login, selfie punch-in, face punch, location prompts, background tracking, push notification, payslip download, chat voice message.

---

## F. Submit for review

App Store Connect → app → **iOS App 1.0.3** (the version page):

1. Paste the listing text and upload the screenshots.
2. **Build** → **+** → choose the TestFlight build.
3. **App Review Information:**
   - Sign-in required: ✅. Enter the **demo username/password** (production server).
   - Contact: your name, phone and email.
   - **Notes** (paste and edit):
     ```
     EktaHR is a B2B employee app. Accounts are created by each company's HR administrator;
     there is no public sign-up, so in-app account creation/deletion does not apply
     (employees are removed by their employer from the EktaHR web portal).

     Demo account: <username> / <password>
     The demo company has geofence and face-match checks relaxed so you can punch in from any location.

     Permissions:
     • Camera — selfie / face-recognition attendance at punch-in.
     • Location (When In Use) — verifies the employee is at the work site when punching in/out.
     • Location (Always) — only if the employer enables tracking for that employee: records
       location between punch-in and punch-out for field-staff visit and distance logs. Stops at punch-out.
     • Motion — detects walking/driving for field visit logs.
     • Microphone / Photos — voice messages and attachments in team chat.
     ```
4. **Release:** choose *Manually release this version* (safer for the first release).
5. Click **Add for Review** → **Submit to App Review**. Review usually takes 1–3 days.

---

## G. Common rejections for this kind of app and how to answer them

| Guideline | Reason | Fix |
|---|---|---|
| 2.1 App Completeness | Reviewer couldn't log in, or the app showed an error screen | Working demo account on **production**; `GoogleService-Info.plist` included |
| 2.5.4 / 5.1.1 Background location | "Always" location not justified | Reply with the tracking explanation above. Optionally attach a short screen recording showing the employer setting and punch-in → tracking → punch-out. |
| 5.1.1(v) Account deletion | "Users can't delete their account" | Reply that accounts are employer-provisioned (B2B), with no self sign-up. |
| 4.2 Minimum functionality | Looks like a website wrapper | Point to the native features: camera punch, face detection, background location, push |
| 2.3.3 Screenshots | Screenshots don't show the app in use | Use real app screens, not just the login page |

If the app is rejected, reply in **Resolution Center** in App Store Connect. You often don't need a new build if it's only an explanation.

---

## H. Updating later
1. Bump `version:` in `pubspec.yaml`, e.g. `1.0.4+15`.
2. Build with Codemagic (or on the Mac) and wait for it to reach TestFlight.
3. App Store Connect → **+ Version** → `1.0.4` → "What's New" text → select build → Submit.
