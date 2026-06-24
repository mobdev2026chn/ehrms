const User = require('../models/User');
const Staff = require('../models/Staff');
const Attendance = require('../models/Attendance');
const Company = require('../models/Company');
const Branch = require('../models/Branch');
const Candidate = require('../models/Candidate');
const { loadAttendanceTemplateForStaff } = require('../utils/resolveStaffAttendanceTemplate');
require('../models/Role');
const TaskSettings = require('../models/TaskSettings');
const mongoose = require('mongoose');
const jwt = require('jsonwebtoken');
const fs = require('fs').promises;
const path = require('path');
const os = require('os');
const https = require('https');
const http = require('http');
const { spawn } = require('child_process');
const { sendOTPEmail } = require('../services/emailService');
const cloudinary = require('cloudinary').v2;
const digitalOceanService = require('../services/digitalOceanService');
// In-process dlib face engine (spawned Python worker over stdin/stdout — no :5005 port).
const faceEngine = require('../services/faceEngine');

cloudinary.config({
    cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
    api_key: process.env.CLOUDINARY_API_KEY,
    api_secret: process.env.CLOUDINARY_API_SECRET
});

const generateToken = (id) => {
    return jwt.sign({ id }, process.env.JWT_SECRET || 'secret', {
        expiresIn: '30d',
    });
};

/** Long-lived token for POST /auth/refresh (must outlive access token). */
const issueRefreshToken = (userId) => {
    const secret = process.env.JWT_SECRET || 'secret';
    return jwt.sign({ id: userId }, secret, { expiresIn: '60d' });
};

// Helper to safely build case-insensitive regex
const buildEmailRegex = (email) => {
    const escaped = email.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    return new RegExp(`^${escaped}$`, 'i');
};

const getRoleIdValue = (user) => {
    const roleId = user?.roleId;
    if (!roleId) return null;
    if (typeof roleId === 'object' && roleId._id) return roleId._id;
    return roleId;
};

const populateRoleIfPresent = async (user) => {
    if (!user) return user;

    const roleId = getRoleIdValue(user);
    if (!roleId || !mongoose.isValidObjectId(roleId)) {
        return user;
    }

    try {
        return await user.populate('roleId');
    } catch (err) {
        console.warn('[Auth] roleId populate skipped:', err?.message);
        return user;
    }
};

// Helper to find or create a user by email, with Candidate fallback
const findOrCreateUserByEmail = async (rawEmail) => {
    if (!rawEmail) return null;

    const email = rawEmail.trim();
    const normalizedEmail = email.toLowerCase();

    // 1. Exact / normalized match
    let user = await User.findOne({ email: normalizedEmail });

    // 2. Case-insensitive regex fallback
    if (!user) {
        user = await User.findOne({ email: buildEmailRegex(email) });
    }

    if (user) {
        return user;
    }

    // 2.5 Staff fallback
    const staff = await Staff.findOne({ email: buildEmailRegex(email) });
    if (staff) {
        // If staff already has a linked user, try to return it
        if (staff.userId) {
            user = await User.findById(staff.userId);
            if (user) return user;
        }

        // Create user from staff
        const randomPassword = Math.random().toString(36).slice(-10) + '!aA1';
        user = await User.create({
            name: staff.name,
            email: normalizedEmail,
            password: randomPassword,
            role: 'Employee',
            companyId: staff.businessId,
            branchId: staff.branchId,
            phone: staff.phone
        });

        // Link staff to new user
        staff.userId = user._id;
        await staff.save();

        return user;
    }

    // 3. Candidate fallback
    const candidate = await Candidate.findOne({
        email: buildEmailRegex(email)
    }).lean();

    if (!candidate) {
        return null;
    }

    // Auto-create basic user from candidate
    const randomPassword = Math.random().toString(36).slice(-10) + '!aA1';

    const name = [candidate.firstName, candidate.lastName].filter(Boolean).join(' ') || candidate.email;

    const newUser = await User.create({
        name,
        email: normalizedEmail,
        password: randomPassword,
        role: 'Employee',
        companyId: candidate.businessId
    });

    return newUser;
};

const login = async (req, res) => {
    try {
        const { email, password, otp } = req.body;

        // Validate required fields
        if (!email || !password) {
            return res.status(400).json({ 
                success: false, 
                error: { message: 'Email and password are required' } 
            });
        }

        // Normalize email for lookup; use case-insensitive match so DB "Boominathanaskeva@..." matches "boominathanaskeva@..."
        const emailNorm = (email || '').trim().toLowerCase();
        const emailRegex = buildEmailRegex(emailNorm);

        // 1. Try to find User (explicitly select password field to ensure it's included)
        let user = await User.findOne({ email: emailRegex })
            .select('+password');
        user = await populateRoleIfPresent(user);
        let staff = null;

        if (user) {
            // Check if user is active
            if (!user.isActive) {
                return res.status(401).json({ success: false, error: { message: 'Account is inactive' } });
            }

            // Check if user has a password set
            if (!user.password) {
                return res.status(401).json({ success: false, error: { message: 'Password not set for this account' } });
            }

            const passwordMatch = await user.matchPassword(password);
            
            if (passwordMatch) {
                staff = await Staff.findOne({ userId: user._id })
                    .populate('branchId')
                    .populate('businessId');
                // Same email as User but staff.userId never set (imports / manual fixes) — link and continue.
                if (!staff) {
                    const staffByEmail = await Staff.findOne({ email: emailRegex })
                        .select('+password')
                        .populate('branchId')
                        .populate('businessId');
                    if (staffByEmail) {
                        const linkedId = staffByEmail.userId ? String(staffByEmail.userId) : '';
                        const okToLink = !linkedId || linkedId === String(user._id);
                        if (okToLink) {
                            if (!staffByEmail.userId) {
                                staffByEmail.userId = user._id;
                                await staffByEmail.save();
                            }
                            staff = staffByEmail;
                        }
                    }
                }
            } else {
                return res.status(401).json({ success: false, error: { message: 'Invalid credentials' } });
            }
        } else {
            // 2. Fallback: Try to find Staff directly (explicitly select password field)
            staff = await Staff.findOne({ email: emailRegex })
                .select('+password')
                .populate('branchId')
                .populate('businessId');

            if (staff) {
                // If staff has no password, check linked User's password
                if (!staff.password) {
                    if (staff.userId) {
                        user = await User.findById(staff.userId)
                            .select('+password');
                        user = await populateRoleIfPresent(user);
                        
                        if (!user || !user.password) {
                            return res.status(401).json({ success: false, error: { message: 'Password not set for this account' } });
                        }
                        
                        // Check if user is active
                        if (!user.isActive) {
                            return res.status(401).json({ success: false, error: { message: 'Account is inactive' } });
                        }
                        
                        const userPasswordMatch = await user.matchPassword(password);
                        if (!userPasswordMatch) {
                            return res.status(401).json({ success: false, error: { message: 'Invalid credentials' } });
                        }
                    } else {
                        return res.status(401).json({ success: false, error: { message: 'Password not set for this account' } });
                    }
                } else {
                    // Staff has password, check it
                    const staffPasswordMatch = await staff.matchPassword(password);
                    if (staffPasswordMatch) {
                        if (staff.userId) {
                            user = await User.findById(staff.userId).select('+password');
                        } else {
                            user = null;
                        }
                        user = await populateRoleIfPresent(user);
                        // Staff rows may exist without userId (or with a stale id). JWT and
                        // middleware expect a User — align with findOrCreateUserByEmail.
                        if (!user) {
                            user = await findOrCreateUserByEmail(staff.email || emailNorm);
                            if (user) {
                                const sid = staff._id;
                                if (!staff.userId || String(staff.userId) !== String(user._id)) {
                                    await Staff.updateOne({ _id: sid }, { $set: { userId: user._id } });
                                }
                                const staffFresh = await Staff.findById(sid)
                                    .populate('branchId')
                                    .populate('businessId');
                                if (staffFresh) staff = staffFresh;
                            }
                        }
                    } else {
                        return res.status(401).json({ success: false, error: { message: 'Invalid credentials' } });
                    }
                }
            } else {
                return res.status(401).json({ success: false, error: { message: 'Invalid credentials' } });
            }
        }

        if (!user) {
            return res.status(401).json({ success: false, error: { message: 'User record not found' } });
        }

        // Mobile app flows require a linked staff profile. Without it, downstream
        // attendance/dashboard/protected endpoints will fail and the app may
        // immediately force logout.
        if (!staff) {
            return res.status(401).json({
                success: false,
                error: { message: 'Staff profile not found for this account. Please contact your administrator.' }
            });
        }

        // Only Active (or On Leave) staff can login; block Deactivated
        if (staff && (staff.status || '').toString().toLowerCase() === 'deactivated') {
            return res.status(401).json({
                success: false,
                error: { message: 'Your account has been deactivated. Please contact HR.' }
            });
        }

        // Prevent candidates from logging in
        if (user.role && user.role.toLowerCase() === 'candidate') {
            return res.status(401).json({ success: false, error: { message: 'login credentials not matching' } });
        }

        // ── Two-Factor Authentication ──────────────────────────────────────────
        if (staff && staff.twoFactorEnabled === true) {
            if (!otp) {
                // No OTP yet — generate one, save it, send email, ask the client to prompt for OTP
                const generatedOtp = Math.floor(100000 + Math.random() * 900000).toString();
                const otpExpiry = new Date(Date.now() + 10 * 60 * 1000); // 10 minutes

                // Load user with select to allow setting extra fields
                const userForOtp = await User.findById(user._id);
                userForOtp.loginOTP = generatedOtp;
                userForOtp.loginOTPExpiry = otpExpiry;
                await userForOtp.save();

                console.log(`[2FA] OTP generated for ${emailNorm}: ${generatedOtp}`);

                // Send 2FA OTP email
                try {
                    await sendOTPEmail(user.email, generatedOtp, 'two-factor-login');
                } catch (emailErr) {
                    console.error('[2FA] Failed to send OTP email:', emailErr.message);
                    // Continue — return requiresOTP even if email fails (logged above)
                }

                return res.json({
                    success: true,
                    requiresOTP: true,
                    message: 'OTP has been sent to your registered email. Please enter the OTP to complete login.'
                });
            }

            // OTP was provided — verify it
            const userForVerify = await User.findById(user._id);
            if (!userForVerify.loginOTP || !userForVerify.loginOTPExpiry) {
                return res.status(400).json({
                    success: false,
                    error: { message: 'No OTP found. Please try logging in again.' }
                });
            }
            if (userForVerify.loginOTP !== otp.toString()) {
                return res.status(400).json({
                    success: false,
                    error: { message: 'Invalid OTP. Please check the code sent to your email.' }
                });
            }
            if (new Date() > userForVerify.loginOTPExpiry) {
                return res.status(400).json({
                    success: false,
                    error: { message: 'OTP has expired. Please try logging in again.' }
                });
            }

            // OTP is valid — clear it so it cannot be reused
            userForVerify.loginOTP = undefined;
            userForVerify.loginOTPExpiry = undefined;
            await userForVerify.save();

            console.log(`[2FA] OTP verified successfully for ${emailNorm}`);
        }
        // ──────────────────────────────────────────────────────────────────────

        // Generate Token
        // Use consistent secret with middleware
        const secret = process.env.JWT_SECRET || 'secret';
        const accessToken = jwt.sign({ id: user._id }, secret, { expiresIn: '30d' });

        // Prepare Response
        let company = staff?.businessId || user.companyId;
        const formattedPermissions = user.roleId?.permissions || [];
        const businessId = staff?.businessId?._id || staff?.businessId || company?._id || company;

        // businessId comes from staffs collection (staff.businessId)
        // Fetch task settings for staff's businessId (enableOtpVerification, autoApprove, etc.)
        let taskSettings = null;
        try {
            if (businessId) {
                const bid = businessId._id ?? businessId;
                taskSettings = await TaskSettings.findOne({
                    $or: [{ companyId: bid }, { businessId: bid }],
                }).lean();
            }
            if (!taskSettings && !businessId) {
                taskSettings = await TaskSettings.findOne().lean();
            }
        } catch (e) {
            console.warn('[Auth] TaskSettings fetch failed:', e?.message);
        }

        const userResponse = {
            id: user._id,
            email: user.email,
            name: user.name,
            role: user.role,
            phone: user.phone,
            companyId: company?._id || company,
            companyName: company && company.name ? company.name : undefined,
            businessId: businessId || company?._id || company,
            permissions: formattedPermissions,
            staffId: staff?._id,
            employeeId: staff?.employeeId,
            avatar: staff?.avatar || user.avatar,
            locationAccess: staff?.locationAccess === true,
            taskSettings: taskSettings?.settings || null,
            branchName: staff?.branchId?.branchName ?? undefined,
        };

        const refreshToken = issueRefreshToken(user._id);

        // Set refresh token as httpOnly cookie (standard practice from Web Backend)
        res.cookie('refreshToken', refreshToken, {
            httpOnly: true,
            secure: process.env.NODE_ENV === 'production',
            sameSite: 'lax',
            maxAge: 60 * 24 * 60 * 60 * 1000, // 60 days (matches JWT expiry)
            path: '/'
        });

        res.json({
            success: true,
            data: {
                user: userResponse,
                accessToken,
                refreshToken // Send it in body too for Mobile App storage if needed
            }
        });

    } catch (error) {
        console.error(error);
        res.status(500).json({ success: false, error: { message: error.message } });
    }
};

/**
 * POST /auth/kiosk-admin-login — Face-kiosk admin gate.
 *
 * Authenticates an EXISTING user against the `users` collection and admits ONLY
 * admin roles (Admin / Super Admin). Unlike POST /auth/login this does NOT
 * require a linked Staff profile — the kiosk is operated by an admin who may not
 * have their own staff record (e.g. leka@gmail.com). Pure credential + role check.
 */
const kioskAdminLogin = async (req, res) => {
    try {
        const { email, password } = req.body;
        if (!email || !password) {
            return res.status(400).json({
                success: false,
                error: { message: 'Email and password are required' }
            });
        }

        const emailNorm = (email || '').trim().toLowerCase();
        const emailRegex = buildEmailRegex(emailNorm);

        // Look up the user in the users collection (password is select:false by default).
        const user = await User.findOne({ email: emailRegex }).select('+password');
        if (!user || !user.password) {
            return res.status(401).json({ success: false, error: { message: 'Invalid credentials' } });
        }
        if (user.isActive === false) {
            return res.status(401).json({ success: false, error: { message: 'Account is inactive' } });
        }

        const passwordMatch = await user.matchPassword(password);
        if (!passwordMatch) {
            return res.status(401).json({ success: false, error: { message: 'Invalid credentials' } });
        }

        // Role gate — only admins may operate the kiosk.
        const role = (user.role || '').toString().trim().toLowerCase();
        const isAdmin = role === 'admin' || role === 'super admin' || role === 'superadmin';
        if (!isAdmin) {
            return res.status(403).json({
                success: false,
                error: { message: 'You are not an admin. Only admin accounts can log in.' }
            });
        }

        const secret = process.env.JWT_SECRET || 'secret';
        const accessToken = jwt.sign({ id: user._id }, secret, { expiresIn: '30d' });

        return res.json({
            success: true,
            data: {
                user: {
                    id: user._id,
                    name: user.name,
                    email: user.email,
                    role: user.role
                },
                accessToken
            }
        });
    } catch (error) {
        console.error('kioskAdminLogin Error:', error);
        return res.status(500).json({ success: false, error: { message: error.message } });
    }
};

const googleLogin = async (req, res) => {
    try {
        const { email } = req.body;

        // Find User
        let user = await User.findOne({ email });
        user = await populateRoleIfPresent(user);
        let staff = null;

        if (user) {
            staff = await Staff.findOne({ userId: user._id })
                .populate('branchId')
                .populate('businessId');

            // Allow if no staff? Maybe. But for HRMS usually need staff.
            // Old logic allowed it.
        } else {
            // Check Staff by email
            staff = await Staff.findOne({ email }).populate('branchId');
            if (staff && staff.userId) {
                user = await User.findById(staff.userId);
                user = await populateRoleIfPresent(user);
            }
        }

        if (!user) {
            return res.status(401).json({ success: false, error: { message: 'User not registered. Please sign up first.' } });
        }

        if (!staff) {
            return res.status(401).json({
                success: false,
                error: { message: 'Staff profile not found for this account. Please contact your administrator.' }
            });
        }

        // Only Active (or On Leave) staff can login; block Deactivated
        if (staff && (staff.status || '').toString().toLowerCase() === 'deactivated') {
            return res.status(401).json({
                success: false,
                error: { message: 'Your account has been deactivated. Please contact HR.' }
            });
        }

        // Prevent candidates from logging in
        if (user.role && user.role.toLowerCase() === 'candidate') {
            return res.status(401).json({ success: false, error: { message: 'login credentials not matching' } });
        }

        const accessToken = generateToken(user._id);
        const refreshToken = issueRefreshToken(user._id);

        let company = staff?.businessId || user.companyId;
        const formattedPermissions = user.roleId?.permissions || [];
        const businessId = staff?.businessId?._id || staff?.businessId || company?._id || company;

        let taskSettings = null;
        try {
            if (businessId) {
                const bid = businessId._id ?? businessId;
                taskSettings = await TaskSettings.findOne({
                    $or: [{ companyId: bid }, { businessId: bid }],
                }).lean();
            }
            if (!taskSettings && !businessId) {
                taskSettings = await TaskSettings.findOne().lean();
            }
        } catch (e) {
            console.warn('[Auth] TaskSettings fetch failed (google):', e?.message);
        }

        const userResponse = {
            id: user._id,
            email: user.email,
            name: user.name,
            role: user.role,
            phone: user.phone,
            companyId: company?._id || company,
            companyName: company && company.name ? company.name : undefined,
            businessId: businessId || company?._id || company,
            permissions: formattedPermissions,
            staffId: staff?._id,
            employeeId: staff?.employeeId,
            avatar: staff?.avatar || user.avatar,
            locationAccess: staff?.locationAccess === true,
            taskSettings: taskSettings?.settings || null,
            branchName: staff?.branchId?.branchName ?? undefined,
        };

        res.json({
            success: true,
            data: {
                user: userResponse,
                accessToken,
                refreshToken
            }
        });

    } catch (error) {
        console.error(error);
        res.status(500).json({ success: false, error: { message: error.message } });
    }
};

/**
 * POST /auth/refresh — public. Body: { refreshToken } → new access + refresh JWTs.
 */
const refreshAccessToken = async (req, res) => {
    try {
        const raw = req.body?.refreshToken;
        if (!raw || typeof raw !== 'string') {
            return res.status(400).json({ success: false, message: 'Refresh token required' });
        }
        const refreshToken = raw.trim().replace(/^"|"$/g, '');
        const secret = process.env.JWT_SECRET || 'secret';
        let decoded;
        try {
            decoded = jwt.verify(refreshToken, secret);
        } catch (e) {
            return res.status(401).json({
                success: false,
                message: 'Invalid or expired refresh token',
                error: e.message
            });
        }
        const user = await User.findById(decoded.id).select('-password');
        if (!user) {
            return res.status(401).json({ success: false, message: 'Not authorized, user not found' });
        }
        const staff = await Staff.findOne({ userId: user._id });
        if (staff && (staff.status || '').toString().toLowerCase() === 'deactivated') {
            return res.status(401).json({
                success: false,
                message: 'Your account has been deactivated. Please contact HR.'
            });
        }
        if (user.role && user.role.toString().toLowerCase() === 'candidate') {
            return res.status(401).json({ success: false, message: 'Not authorized' });
        }
        const accessToken = generateToken(user._id);
        const newRefreshToken = issueRefreshToken(user._id);
        res.json({
            success: true,
            data: {
                accessToken,
                refreshToken: newRefreshToken
            }
        });
    } catch (error) {
        console.error('[authController] refreshAccessToken:', error);
        res.status(500).json({ success: false, message: error.message });
    }
};

const register = async (req, res) => {
    const { name, email, password } = req.body;
    try {
        const userExists = await User.findOne({ email });
        if (userExists) return res.status(400).json({ success: false, error: { message: 'User already exists' } });

        const user = await User.create({ name, email, password });
        if (user) {
            const accessToken = generateToken(user._id);
            res.status(201).json({
                success: true,
                data: {
                    user: {
                        id: user._id,
                        name: user.name,
                        email: user.email
                    },
                    accessToken
                }
            });
        }
    } catch (error) {
        res.status(500).json({ success: false, error: { message: error.message } });
    }
};

const getProfile = async (req, res) => {
    try {
        // req.user and req.staff are populated by authMiddleware
        const user = req.user;
        const staff = req.staff;

        if (!user) {
            return res.status(404).json({ success: false, error: { message: 'User not found' } });
        }

        // Re-fetch to ensure latest data and populated fields
        let fullUser = await User.findById(user._id);
        fullUser = await populateRoleIfPresent(fullUser);

        let fullStaff = null;
        let candidateData = null;

        if (staff) {
            fullStaff = await Staff.findById(staff._id)
                .populate('branchId')
                // App does not need full company subscription/plan payload in profile.
                // Keep only settings used by attendance/salary calculations.
                // Full settings subtree so embedded attendance.shifts[].workHours is not omitted by partial paths.
                .populate({
                    path: 'businessId',
                    select: '_id settings',
                })
                .populate('weeklyHolidayTemplateId')
                .populate('candidateId') // Populate candidate to get education, experience, documents
                .populate('department') // Assuming department might be a ref or string, populating just in case
                .populate('designation'); // Same here

            // Extract candidate data if available
            if (fullStaff?.candidateId) {
                candidateData = fullStaff.candidateId;
            } else if (fullStaff?.email) {
                // Fallback: If candidateId is not populated but staff has email, try to find candidate by email
                candidateData = await Candidate.findOne({
                    email: fullStaff.email.toLowerCase(),
                    businessId: fullStaff.businessId
                }).lean();
            }
        }

        const branchName = fullStaff?.branchId?.branchName ?? null;

        let staffDataPayload = null;
        if (fullStaff) {
            const staffPlain = fullStaff.toObject();
            const atRef = fullStaff.attendanceTemplateId;
            const attendanceTemplateIdOut = atRef == null
                ? null
                : (typeof atRef === 'object' && atRef._id != null
                    ? String(atRef._id)
                    : String(atRef));
            staffDataPayload = {
                ...staffPlain,
                attendanceTemplateId: attendanceTemplateIdOut,
                candidateId: candidateData || fullStaff.candidateId,
                employmentIds: {
                    uan: fullStaff.uan,
                    pan: fullStaff.pan,
                    aadhaar: fullStaff.aadhaar,
                    pfNumber: fullStaff.pfNumber,
                    esiNumber: fullStaff.esiNumber
                }
            };
            // staff.attendanceTemplateId must reference a real attendancetemplates row (and same business when set)
            if (staffDataPayload.attendanceTemplateId) {
                const tdoc = await loadAttendanceTemplateForStaff({
                    _id: fullStaff._id,
                    businessId: fullStaff.businessId,
                    attendanceTemplateId: staffDataPayload.attendanceTemplateId
                });
                if (!tdoc) staffDataPayload.attendanceTemplateId = null;
            }
        }

        res.status(200).json({
            success: true,
            data: {
                profile: {
                    name: fullUser.name,
                    email: fullUser.email,
                    phone: fullStaff?.phone || fullUser.phone,
                    avatar: fullUser.avatar || fullStaff?.avatar,
                    role: fullUser.role
                },
                branchName: branchName,
                staffData: staffDataPayload
            }
        });

    } catch (error) {
        console.error('getProfile Error:', error);
        res.status(500).json({ success: false, error: { message: error.message } });
    }
};

const updateProfile = async (req, res) => {
    try {
        const { name, phone, avatar } = req.body;
        const userId = req.user._id;

        const user = await User.findById(userId);
        if (!user) return res.status(404).json({ success: false, error: { message: 'User not found' } });

        if (name) user.name = name;
        if (phone) user.phone = phone;
        // Support avatar delete: when avatar/photoUrl key is present, update (including clearing to empty)
        if ('avatar' in req.body || 'photoUrl' in req.body) {
            const avatarVal = req.body.avatar ?? req.body.photoUrl ?? null;
            user.avatar = (avatarVal && String(avatarVal).trim()) ? avatarVal : null;
        }

        await user.save();

        if (req.staff) {
            const {
                gender, maritalStatus, dob, bloodGroup, address, bankDetails,
                employmentIds, uan, pan, aadhaar, pfNumber, esiNumber,
                designation, department, shiftName, shiftId, status,
                isGpsEnabled, isGpsAllowed, isEnabledPreciseLocation
            } = req.body;

            const updateData = {};
            if (name) updateData.name = name;
            if (phone) updateData.phone = phone;
            if ('avatar' in req.body || 'photoUrl' in req.body) {
                const avatarVal = req.body.avatar ?? req.body.photoUrl ?? null;
                updateData.avatar = (avatarVal && String(avatarVal).trim()) ? avatarVal : null;
            }
            if (gender) updateData.gender = gender;
            if (maritalStatus) updateData.maritalStatus = maritalStatus;
            if (dob) updateData.dob = dob;
            if (bloodGroup) updateData.bloodGroup = bloodGroup;
            if (address) updateData.address = address;
            if (bankDetails) updateData.bankDetails = bankDetails;

            // Professional details
            if (designation) updateData.designation = designation;
            if (department) updateData.department = department;
            if (shiftName) updateData.shiftName = shiftName;
            if (shiftId !== undefined) updateData.shiftId = shiftId || null;
            if (status) updateData.status = status;
            if (typeof isGpsEnabled === 'boolean') {
                updateData.isGpsEnabled = isGpsEnabled;
            }
            if (typeof isGpsAllowed === 'string' && isGpsAllowed.trim()) {
                updateData.isGpsAllowed = isGpsAllowed.trim();
            }
            if (typeof isEnabledPreciseLocation === 'boolean') {
                updateData.isEnabledPreciseLocation = isEnabledPreciseLocation;
            }

            // Handle employment IDs
            if (employmentIds) {
                updateData.uan = employmentIds.uan;
                updateData.pan = employmentIds.pan;
                updateData.aadhaar = employmentIds.aadhaar;
                updateData.pfNumber = employmentIds.pfNumber;
                updateData.esiNumber = employmentIds.esiNumber;
            }
            // Or direct fields
            if (uan !== undefined) updateData.uan = uan;
            if (pan !== undefined) updateData.pan = pan;
            if (aadhaar !== undefined) updateData.aadhaar = aadhaar;
            if (pfNumber !== undefined) updateData.pfNumber = pfNumber;
            if (esiNumber !== undefined) updateData.esiNumber = esiNumber;

            // App sync: per-day net/gross from web payroll preview (salaryBasis ÷ fullMonth WD) — fines / salary UI parity.
            const { appPerDayNetSalary, appPerdayGrossSalary } = req.body;
            if (appPerDayNetSalary !== undefined && appPerDayNetSalary !== null && appPerDayNetSalary !== '') {
                const v = Number(appPerDayNetSalary);
                if (Number.isFinite(v) && v >= 0 && v < 1e9) {
                    updateData.appPerDayNetSalary = Math.round(v * 100) / 100;
                }
            }
            if (appPerdayGrossSalary !== undefined && appPerdayGrossSalary !== null && appPerdayGrossSalary !== '') {
                const v = Number(appPerdayGrossSalary);
                if (Number.isFinite(v) && v >= 0 && v < 1e9) {
                    updateData.appPerdayGrossSalary = Math.round(v * 100) / 100;
                }
            }
            if (Object.keys(updateData).length > 0) {
                if (updateData.appPerDayNetSalary != null || updateData.appPerdayGrossSalary != null) {
                    console.log(
                        '[updateProfile] app per-day from client:',
                        `appPerDayNetSalary=${updateData.appPerDayNetSalary}`,
                        `appPerdayGrossSalary=${updateData.appPerdayGrossSalary}`
                    );
                }
                await Staff.findByIdAndUpdate(req.staff._id, updateData, {
                    runValidators: false,
                    new: true
                });
            }
        }

        res.json({
            success: true,
            message: 'Profile updated successfully',
            data: {
                user: {
                    id: user._id,
                    name: user.name,
                    phone: user.phone,
                    avatar: user.avatar
                }
            }
        });

    } catch (error) {
        console.error('updateProfile Error:', error);
        res.status(500).json({ success: false, error: { message: error.message } });
    }
};

/**
 * Update education details for current user's candidate record.
 * Education is stored on Candidate model; finds or creates candidate linked to staff.
 */
const updateEducation = async (req, res) => {
    try {
        const staff = req.staff;
        if (!staff) {
            return res.status(404).json({ success: false, error: { message: 'Staff record not found' } });
        }

        const education = req.body.education;
        if (!Array.isArray(education)) {
            return res.status(400).json({
                success: false,
                error: { message: 'education must be an array' }
            });
        }

        // Normalize education entries to match Candidate schema
        const normalizedEducation = education.map((edu) => ({
            qualification: edu.qualification || '',
            courseName: edu.courseName || edu.course || '',
            institution: edu.institution || '',
            university: edu.university || '',
            yearOfPassing: edu.yearOfPassing != null ? String(edu.yearOfPassing) : '',
            percentage: edu.percentage != null ? String(edu.percentage) : '',
            cgpa: edu.cgpa != null ? String(edu.cgpa) : ''
        }));

        let candidate = await Candidate.findById(staff.candidateId);
        if (!candidate && staff.email) {
            candidate = await Candidate.findOne({
                email: staff.email.toLowerCase(),
                businessId: staff.businessId
            });
        }

        if (!candidate) {
            // Create a minimal candidate for this staff so we can store education
            candidate = await Candidate.create({
                firstName: (staff.name || 'Staff').split(' ')[0] || 'Staff',
                lastName: (staff.name || '').split(' ').slice(1).join(' ') || 'User',
                email: staff.email,
                phone: staff.phone || '',
                position: staff.designation || 'Employee',
                primarySkill: 'General',
                status: 'Applied',
                businessId: staff.businessId,
                education: normalizedEducation
            });
            // Update staff.candidateId without triggering full validation
            await Staff.findByIdAndUpdate(
                staff._id,
                { candidateId: candidate._id },
                { runValidators: false, new: false }
            );
        } else {
            candidate.education = normalizedEducation;
            await candidate.save();
        }

        const updatedCandidate = await Candidate.findById(candidate._id).lean();
        res.json({
            success: true,
            message: 'Education updated successfully',
            data: {
                education: updatedCandidate.education || []
            }
        });
    } catch (error) {
        console.error('updateEducation Error:', error);
        res.status(500).json({ success: false, error: { message: error.message } });
    }
};

/**
 * Update experience details for current user's candidate record.
 * Experience is stored on Candidate model; finds or creates candidate linked to staff.
 */
const updateExperience = async (req, res) => {
    try {
        const staff = req.staff;
        if (!staff) {
            return res.status(404).json({ success: false, error: { message: 'Staff record not found' } });
        }

        const experience = req.body.experience;
        if (!Array.isArray(experience)) {
            return res.status(400).json({
                success: false,
                error: { message: 'experience must be an array' }
            });
        }

        // Normalize experience entries to match Candidate schema
        const normalizedExperience = experience.map((exp) => {
            const result = {
                company: exp.company || '',
                role: exp.role || '',
                designation: exp.designation || '',
                keyResponsibilities: exp.keyResponsibilities || '',
                reasonForLeaving: exp.reasonForLeaving || ''
            };

            // Handle dates - convert string to Date if provided
            if (exp.durationFrom) {
                const fromDate = new Date(exp.durationFrom);
                result.durationFrom = isNaN(fromDate.getTime()) ? null : fromDate;
            } else {
                result.durationFrom = null;
            }

            if (exp.durationTo) {
                const toDate = new Date(exp.durationTo);
                result.durationTo = isNaN(toDate.getTime()) ? null : toDate;
            } else {
                result.durationTo = null;
            }

            return result;
        });

        let candidate = await Candidate.findById(staff.candidateId);
        if (!candidate && staff.email) {
            candidate = await Candidate.findOne({
                email: staff.email.toLowerCase(),
                businessId: staff.businessId
            });
        }

        if (!candidate) {
            // Create a minimal candidate for this staff so we can store experience
            candidate = await Candidate.create({
                firstName: (staff.name || 'Staff').split(' ')[0] || 'Staff',
                lastName: (staff.name || '').split(' ').slice(1).join(' ') || 'User',
                email: staff.email,
                phone: staff.phone || '',
                position: staff.designation || 'Employee',
                primarySkill: 'General',
                status: 'Applied',
                businessId: staff.businessId,
                experience: normalizedExperience
            });
            // Update staff.candidateId without triggering full validation
            await Staff.findByIdAndUpdate(
                staff._id,
                { candidateId: candidate._id },
                { runValidators: false, new: false }
            );
        } else {
            candidate.experience = normalizedExperience;
            await candidate.save();
        }

        const updatedCandidate = await Candidate.findById(candidate._id).lean();
        res.json({
            success: true,
            message: 'Experience updated successfully',
            data: {
                experience: updatedCandidate.experience || []
            }
        });
    } catch (error) {
        console.error('updateExperience Error:', error);
        res.status(500).json({ success: false, error: { message: error.message } });
    }
};

// -------------------------------
// Password reset with OTP flow
// -------------------------------

// Phase 1: Request OTP
const forgotPassword = async (req, res) => {
    console.log(`[ForgotPassword] Route handler called - Method: ${req.method}, Path: ${req.path}, OriginalUrl: ${req.originalUrl}`);
    try {
        const { email } = req.body;

        if (!email) {
            return res.status(400).json({
                success: false,
                error: { message: 'Email is required' }
            });
        }

        // First check if email exists in Staff collection
        const emailRegex = buildEmailRegex(email.trim());
        const staff = await Staff.findOne({ email: emailRegex });

        if (!staff) {
            console.log(`[ForgotPassword] ❌ Email not found in Staff collection: ${email}`);
            return res.status(404).json({
                success: false,
                error: { message: 'No registered account with this email' }
            });
        }

        console.log(`[ForgotPassword] ✅ Email found in Staff collection: ${email}`);

        // Get or create user associated with this staff
        const user = await findOrCreateUserByEmail(email);

        if (!user) {
            console.log(`[ForgotPassword] ❌ Failed to get/create user for staff email: ${email}`);
            return res.status(500).json({
                success: false,
                error: { message: 'Failed to process password reset request' }
            });
        }

        const otp = Math.floor(100000 + Math.random() * 900000).toString();
        const expiry = new Date(Date.now() + 10 * 60 * 1000); // 10 minutes

        console.log(`[ForgotPassword] Generating OTP for email: ${email}`);
        console.log(`[ForgotPassword] OTP: ${otp} (expires at: ${expiry.toISOString()})`);

        user.resetPasswordOTP = otp;
        user.resetPasswordOTPExpiry = expiry;
        await user.save();

        console.log(`[ForgotPassword] OTP saved to database for user: ${user._id}`);

        // Send OTP to normalized email (trim + lowercase) to avoid provider issues with casing/spaces for "some" recipients
        const emailToSend = (staff.email || user.email || email).trim().toLowerCase();
        if (!emailToSend || !emailToSend.includes('@')) {
            console.error(`[ForgotPassword] ❌ Invalid email to send: ${emailToSend ? '(invalid format)' : '(empty)'}`);
            return res.status(200).json({
                success: false,
                message: 'We couldn\'t deliver the OTP to your email. Please try again later or contact your administrator.'
            });
        }
        console.log(`[ForgotPassword] Sending OTP email to: ${emailToSend}`);
        const emailResult = await sendOTPEmail(emailToSend, otp);

        if (!emailResult.success) {
            console.error(`[ForgotPassword] ❌ Failed to send OTP email: ${emailResult.error}`);
            return res.status(200).json({
                success: false,
                message: 'We couldn\'t deliver the OTP to your email. Please try again later or contact your administrator to check email configuration.'
            });
        }

        console.log(`[ForgotPassword] ✅ OTP email sent successfully to ${emailToSend}`);
        console.log(`[ForgotPassword] Email Message ID: ${emailResult.messageId}`);

        return res.status(200).json({
            success: true,
            message: 'OTP has been sent to your registered email address'
        });
    } catch (error) {
        console.error('forgotPassword Error:', error);
        return res.status(500).json({
            success: false,
            error: { message: error.message }
        });
    }
};

// Phase 2: Verify OTP
const verifyOTP = async (req, res) => {
    try {
        const { email, otp } = req.body;

        console.log(`[VerifyOTP] Verifying OTP for email: ${email}`);

        if (!email || !otp) {
            console.log(`[VerifyOTP] ❌ Missing email or OTP`);
            return res.status(400).json({
                success: false,
                error: { message: 'Email and OTP are required' }
            });
        }

        // First check if email exists in Staff collection
        const emailRegex = buildEmailRegex(email.trim());
        const staff = await Staff.findOne({ email: emailRegex });

        if (!staff) {
            console.log(`[VerifyOTP] ❌ Email not found in Staff collection: ${email}`);
            return res.status(404).json({
                success: false,
                error: { message: 'No registered account with this email' }
            });
        }

        const user = await findOrCreateUserByEmail(email);

        if (!user || !user.resetPasswordOTP || !user.resetPasswordOTPExpiry) {
            console.log(`[VerifyOTP] ❌ No OTP found for email: ${email}`);
            return res.status(400).json({
                success: false,
                error: { message: 'Invalid or expired OTP' }
            });
        }

        console.log(`[VerifyOTP] Stored OTP: ${user.resetPasswordOTP}, Provided OTP: ${otp}`);
        console.log(`[VerifyOTP] OTP expires at: ${user.resetPasswordOTPExpiry.toISOString()}`);

        if (user.resetPasswordOTP !== otp) {
            console.log(`[VerifyOTP] ❌ OTP mismatch`);
            return res.status(400).json({
                success: false,
                error: { message: 'Invalid OTP' }
            });
        }

        if (new Date() > user.resetPasswordOTPExpiry) {
            console.log(`[VerifyOTP] ❌ OTP expired`);
            return res.status(400).json({
                success: false,
                error: { message: 'OTP has expired' }
            });
        }

        console.log(`[VerifyOTP] ✅ OTP verified successfully for ${email}`);

        return res.status(200).json({
            success: true,
            message: 'OTP verified successfully'
        });
    } catch (error) {
        console.error('verifyOTP Error:', error);
        return res.status(500).json({
            success: false,
            error: { message: error.message }
        });
    }
};

// Phase 3: Reset password
const resetPassword = async (req, res) => {
    try {
        const { email, otp, newPassword } = req.body;

        if (!email || !otp || !newPassword) {
            return res.status(400).json({
                success: false,
                error: { message: 'Email, OTP and new password are required' }
            });
        }

        // First check if email exists in Staff collection
        const emailRegex = buildEmailRegex(email.trim());
        const staff = await Staff.findOne({ email: emailRegex });

        if (!staff) {
            console.log(`[ResetPassword] ❌ Email not found in Staff collection: ${email}`);
            return res.status(404).json({
                success: false,
                error: { message: 'No registered account with this email' }
            });
        }

        const user = await findOrCreateUserByEmail(email);

        if (!user || !user.resetPasswordOTP || !user.resetPasswordOTPExpiry) {
            return res.status(400).json({
                success: false,
                error: { message: 'Invalid or expired OTP' }
            });
        }

        if (user.resetPasswordOTP !== otp) {
            return res.status(400).json({
                success: false,
                error: { message: 'Invalid OTP' }
            });
        }

        if (new Date() > user.resetPasswordOTPExpiry) {
            return res.status(400).json({
                success: false,
                error: { message: 'OTP has expired' }
            });
        }

        user.password = newPassword; // Will be hashed by pre-save hook
        user.resetPasswordOTP = undefined;
        user.resetPasswordOTPExpiry = undefined;
        await user.save();

        return res.status(200).json({
            success: true,
            message: 'Password has been reset successfully'
        });
    } catch (error) {
        console.error('resetPassword Error:', error);
        return res.status(500).json({
            success: false,
            error: { message: error.message }
        });
    }
};

// -------------------------------
// Change password (old + new)
// -------------------------------

const changePassword = async (req, res) => {
    try {
        const { oldPassword, newPassword } = req.body;

        if (!oldPassword || !newPassword) {
            return res.status(400).json({
                success: false,
                error: { message: 'Old password and new password are required' }
            });
        }

        if (oldPassword === newPassword) {
            return res.status(400).json({
                success: false,
                error: { message: 'New password must be different from old password' }
            });
        }

        const userId = req.user?._id;
        if (!userId) {
            return res.status(401).json({
                success: false,
                error: { message: 'Not authenticated' }
            });
        }

        // Load user with password field
        const user = await User.findById(userId).select('+password');
        if (!user || !user.password) {
            return res.status(404).json({
                success: false,
                error: { message: 'User not found or password not set' }
            });
        }

        const isMatch = await user.matchPassword(oldPassword);
        if (!isMatch) {
            return res.status(401).json({
                success: false,
                error: { message: 'Old password is incorrect' }
            });
        }

        user.password = newPassword; // pre-save hook will hash
        await user.save();

        return res.status(200).json({
            success: true,
            message: 'Password updated successfully'
        });
    } catch (error) {
        console.error('changePassword Error:', error);
        return res.status(500).json({
            success: false,
            error: { message: error.message }
        });
    }
};

// -------------------------------
// Update profile photo (Digital Ocean S3)
// -------------------------------

const updateProfilePhoto = async (req, res) => {
    try {
        if (!req.file || !req.file.buffer) {
            return res.status(400).json({
                success: false,
                error: { message: 'No file uploaded' }
            });
        }

        const userId = req.user?._id;
        if (!userId) {
            return res.status(401).json({
                success: false,
                error: { message: 'Not authenticated' }
            });
        }

        const companyId = req.staff?.businessId ? String(req.staff.businessId) : undefined;
        const employeeName = req.staff?.name || req.user?.name;

        const uploadResult = await digitalOceanService.uploadImage(req.file.buffer, undefined, {
            req,
            companyId,
            employeeName,
            category: 'employees',
            subfolder: 'avatar',
            format: req.file.mimetype?.includes('png') ? 'png' : 'jpg',
        });

        if (!uploadResult.success) {
            return res.status(500).json({
                success: false,
                error: { message: uploadResult.error || 'Failed to upload profile photo' }
            });
        }

        const photoUrl = uploadResult.url;

        // Update User avatar
        const user = await User.findById(userId);
        if (user) {
            user.avatar = photoUrl;
            await user.save();
        }

        // Update Staff avatar if staff record exists
        if (req.staff && req.staff._id) {
            await Staff.findByIdAndUpdate(
                req.staff._id,
                { avatar: photoUrl },
                { new: true }
            );
        }

        return res.status(200).json({
            success: true,
            message: 'Profile photo updated successfully',
            data: { photoUrl }
        });
    } catch (error) {
        console.error('updateProfilePhoto Error:', error);
        return res.status(500).json({
            success: false,
            error: { message: error.message }
        });
    }
};

// -------------------------------
// Verify face (selfie vs profile photo)
// -------------------------------
// Persistent face-verify service (server.py). Loads ArcFace once and answers in
// ~0.3s, so the punch keeps a hard face-match gate without spawning Python and
// reloading the model every time. Falls back to the one-shot CLI when it's down.
const FACE_VERIFY_URL = process.env.FACE_VERIFY_URL || 'http://127.0.0.1:5005';

// POST selfie + reference URL to the persistent service. Resolves {match, error};
// rejects on connection/timeout so the caller can fall back to the CLI.
function callFaceVerifyService(selfie, referenceUrl) {
    return new Promise((resolve, reject) => {
        let body;
        try {
            body = JSON.stringify({ selfie, reference_url: referenceUrl });
        } catch (e) {
            return reject(e);
        }
        const u = new URL('/verify', FACE_VERIFY_URL);
        const client = u.protocol === 'https:' ? https : http;
        const r = client.request({
            method: 'POST',
            hostname: u.hostname,
            port: u.port || (u.protocol === 'https:' ? 443 : 80),
            path: u.pathname,
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(body),
            },
            timeout: 20000,
        }, (resp) => {
            let data = '';
            resp.on('data', (c) => { data += c; });
            resp.on('end', () => {
                try {
                    const out = JSON.parse(data || '{}');
                    resolve({
                        match: !!out.match,
                        distance: typeof out.distance === 'number' ? out.distance : null,
                        error: out.error || null,
                    });
                } catch (e) {
                    reject(e);
                }
            });
        });
        r.on('error', reject);
        r.on('timeout', () => { r.destroy(new Error('face-verify service timeout')); });
        r.write(body);
        r.end();
    });
}

// POST an image to the face service /embed endpoint. Resolves {embedding, error};
// rejects on connection/timeout so the caller can treat it as "service unavailable".
function callEmbedService(image) {
    return new Promise((resolve, reject) => {
        let body;
        try {
            body = JSON.stringify({ image });
        } catch (e) {
            return reject(e);
        }
        const u = new URL('/embed', FACE_VERIFY_URL);
        const client = u.protocol === 'https:' ? https : http;
        const r = client.request({
            method: 'POST',
            hostname: u.hostname,
            port: u.port || (u.protocol === 'https:' ? 443 : 80),
            path: u.pathname,
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(body),
            },
            timeout: 20000,
        }, (resp) => {
            let data = '';
            resp.on('data', (c) => { data += c; });
            resp.on('end', () => {
                try {
                    const out = JSON.parse(data || '{}');
                    resolve({
                        embedding: Array.isArray(out.embedding) ? out.embedding : null,
                        error: out.error || null,
                    });
                } catch (e) {
                    reject(e);
                }
            });
        });
        r.on('error', reject);
        r.on('timeout', () => { r.destroy(new Error('embed service timeout')); });
        r.write(body);
        r.end();
    });
}

// Euclidean distance between two equal-length numeric vectors (dlib face descriptors).
function euclideanDistance(a, b) {
    if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return Infinity;
    let sum = 0;
    for (let i = 0; i < a.length; i++) {
        const d = a[i] - b[i];
        sum += d * d;
    }
    return Math.sqrt(sum);
}

// dlib same-person boundary (matches the Python service default / face app).
// Used by the 1-to-1 VERIFY path (verifyFace), where we already know WHO the live
// face claims to be and only confirm it's the same person.
const FACE_MATCH_THRESHOLD = parseFloat(process.env.FACE_MATCH_THRESHOLD || '0.50');

// 1-to-MANY IDENTIFY boundary (identifyFromEnrollments → kiosk identifyFace +
// app verifyIdentity). Identification must be STRICTER than 1-to-1 verification:
// with N enrolled faces in the gallery, the chance that *some* unrelated face
// falls under a loose threshold grows with N, so a flat 0.50 false-accepts a
// brand-new (unenrolled) person as whichever enrolled face is marginally closest.
// That both mis-identifies new users AND, because the closest enrolled face
// varies frame-to-frame, makes the kiosk flash "different" people and never
// surface the enroll prompt. Tighten the accept boundary here.
const FACE_IDENTIFY_THRESHOLD = parseFloat(process.env.FACE_IDENTIFY_THRESHOLD || '0.44');

// Minimum gap the best candidate must beat the 2nd-best (different person) by for
// the identification to be unambiguous. If the top two enrolled people are within
// this margin of each other, the live face is too ambiguous to assign to either —
// treat it as NOT recognized (→ at-kiosk enroll) instead of guessing.
const FACE_IDENTIFY_MARGIN = parseFloat(process.env.FACE_IDENTIFY_MARGIN || '0.06');

// Decide whether a 1-to-many identify result is a CONFIDENT, unambiguous match.
// best/second are { staff, distance } (second may be null when only one person is
// enrolled). A match must be both close enough (< identify threshold) AND clearly
// separated from the next-closest different person (>= margin).
function isConfidentIdentification(best, second) {
    if (!best || typeof best.distance !== 'number') return false;
    if (best.distance > FACE_IDENTIFY_THRESHOLD) return false;
    if (second && typeof second.distance === 'number') {
        if (second.distance - best.distance < FACE_IDENTIFY_MARGIN) return false;
    }
    return true;
}

// Slow fallback: download the reference, write the selfie to temp, and run the
// one-shot CLI (reloads the model each call). Used only when the service is down.
async function verifyFaceViaCli(selfie, referenceUrl) {
    let selfiePath = null;
    let profilePath = null;
    const tmpDir = os.tmpdir();
    try {
        const base64Match = selfie.match(/^data:image\/\w+;base64,(.+)$/);
        const base64Data = base64Match ? base64Match[1] : selfie;
        selfiePath = path.join(tmpDir, `selfie_${Date.now()}.jpg`);
        await fs.writeFile(selfiePath, Buffer.from(base64Data, 'base64'));

        profilePath = path.join(tmpDir, `profile_${Date.now()}.jpg`);
        await new Promise((resolve, reject) => {
            const url = new URL(referenceUrl);
            const client = url.protocol === 'https:' ? https : http;
            const dreq = client.get(referenceUrl, (resp) => {
                if (resp.statusCode !== 200) {
                    reject(new Error(`Reference fetch failed: ${resp.statusCode}`));
                    return;
                }
                const chunks = [];
                resp.on('data', (c) => chunks.push(c));
                resp.on('end', () => {
                    fs.writeFile(profilePath, Buffer.concat(chunks)).then(resolve).catch(reject);
                });
            });
            dreq.on('error', reject);
            dreq.setTimeout(15000, () => { dreq.destroy(); reject(new Error('Timeout')); });
        });
    } catch (e) {
        if (selfiePath) await fs.unlink(selfiePath).catch(() => {});
        if (profilePath) await fs.unlink(profilePath).catch(() => {});
        return { match: false, error: 'Could not prepare images for verification.' };
    }

    const scriptDir = path.join(__dirname, '../../face_verify');
    const scriptPath = path.join(scriptDir, 'face_verify.py');
    const venvPythonWin = path.join(scriptDir, 'venv', 'Scripts', 'python.exe');
    const venvPythonUnix = path.join(scriptDir, 'venv', 'bin', 'python');
    const venvPython = process.platform === 'win32' ? venvPythonWin : venvPythonUnix;
    const py = require('fs').existsSync(venvPython) ? venvPython : (process.platform === 'win32' ? 'python' : 'python3');

    const result = await new Promise((resolve) => {
        const child = spawn(py, [scriptPath, selfiePath, profilePath], { cwd: scriptDir, timeout: 90000 });
        let stdout = '';
        let stderr = '';
        child.stdout.on('data', (d) => { stdout += d.toString(); });
        child.stderr.on('data', (d) => { stderr += d.toString(); });
        child.on('error', () => resolve({ match: false, error: 'Face verification not available' }));
        child.on('close', () => {
            try {
                const out = JSON.parse(stdout.trim() || '{}');
                resolve({
                    match: !!out.match,
                    distance: typeof out.distance === 'number' ? out.distance : null,
                    error: out.error || null,
                });
            } catch {
                resolve({ match: false, distance: null, error: stderr || 'Verification failed' });
            }
        });
    });

    if (selfiePath) await fs.unlink(selfiePath).catch(() => {});
    if (profilePath) await fs.unlink(profilePath).catch(() => {});
    return result;
}

const verifyFace = async (req, res) => {
    try {
        const { selfie } = req.body || {};
        if (!selfie || typeof selfie !== 'string') {
            return res.status(400).json({
                success: false,
                match: false,
                error: { message: 'Selfie image (base64 data URL) is required.' }
            });
        }

        const user = req.user;
        const staff = req.staff;
        const fullUser = await User.findById(user._id).select('faceReferenceImage faceFirstImage avatar').lean();
        let fullStaff = null;
        if (staff && staff._id) fullStaff = await Staff.findById(staff._id).select('faceReferenceImage faceFirstImage avatar faceEnrollEmbeddings').lean();

        // PRIMARY PATH — dedicated face ENROLLMENT. If the user registered their face,
        // match the live selfie against those FIXED enrolled embeddings (no rolling
        // drift). This is the reliable path: same approach as the face-attendance app
        // (stored samples + min euclidean distance, threshold 0.50). Computed in EHRMS.
        const enrollEmbeddings = Array.isArray(fullStaff?.faceEnrollEmbeddings)
            ? fullStaff.faceEnrollEmbeddings : [];
        if (enrollEmbeddings.length > 0) {
            let liveEmbedding = null;
            try {
                // EXISTING (lenient embed, no liveness/position guards) — replaced
                // by the face-attendance app's STRICT kiosk pipeline so a punch/break
                // selfie must be a single, centered, correctly-distanced, live face.
                // const r = await faceEngine.embed(selfie);
                const r = await faceEngine.embedLive(selfie);
                liveEmbedding = r.embedding;
                if (!liveEmbedding) {
                    return res.status(200).json({
                        success: true, match: false, enrolled: true,
                        message: toUserFriendlyVerifyMessage(r.error || 'No face detected'),
                    });
                }
            } catch (e) {
                console.warn('[verifyFace] embed engine unavailable:', e?.message);
                return res.status(200).json({
                    success: false, match: false, enrolled: true,
                    message: 'Face verification failed. Please try again.',
                });
            }
            let best = Infinity;
            for (const emb of enrollEmbeddings) {
                const d = euclideanDistance(liveEmbedding, emb);
                if (d < best) best = d;
            }
            const matched = best <= FACE_MATCH_THRESHOLD;
            console.log(`[verifyFace] staff=${staff?._id} ENROLLED samples=${enrollEmbeddings.length} matched=${matched} bestDistance=${best.toFixed(4)}`);
            return res.status(200).json({
                success: true,
                match: matched,
                enrolled: true,
                message: matched ? 'Photo matched' : 'Face not matching. Please try again.',
            });
        }

        // STRICT LIVE GATE (face-attendance app's kiosk pipeline) — applied to the
        // fallback path too: even a not-yet-enrolled user's selfie must be a single,
        // centered, correctly-distanced, live face before we accept/seed it. A guard
        // or anti-spoof failure short-circuits here with an actionable message.
        let liveEmbedding = null;
        try {
            const guard = await faceEngine.embedLive(selfie);
            if (!guard.embedding) {
                return res.status(200).json({
                    success: true, match: false, enrolled: false,
                    message: toUserFriendlyVerifyMessage(guard.error || 'No face detected'),
                });
            }
            // Keep the strict live embedding — on a successful first punch it becomes
            // the user's canonical enrollment (auto-enroll, below).
            liveEmbedding = guard.embedding;
        } catch (e) {
            console.warn('[verifyFace] live-guard engine unavailable:', e?.message);
            return res.status(200).json({
                success: false, match: false, enrolled: false,
                message: 'Face verification failed. Please try again.',
            });
        }

        // FALLBACK PATH — user has NOT enrolled yet. Validate against the user's OWN
        // images (rolling reference / first / avatar) so existing users aren't blocked,
        // and flag enrolled:false so the app can prompt a one-time enrollment.
        // Validate the selfie against ANY of the user's OWN enrolled images, in
        // priority order:
        //   1. faceReferenceImage — the rolling self-reference (most recent punch),
        //   2. faceFirstImage     — the permanent enrollment selfie (never overwritten),
        //   3. avatar             — onboarding/profile photo.
        // Accepting any one of these prevents a single POOR rolling reference (e.g. a
        // bad-lighting / off-angle prior punch) from permanently locking out a
        // legitimate user — the classic failure mode of a rolling self-reference. It
        // does NOT weaken cross-user protection: every candidate is the same user's own
        // face, and the 1-to-many buddy-punch guard (FaceIdentityGuard) runs separately.
        // Only when the user has NO image anywhere do we accept blindly (nothing to
        // compare against — the punch then seeds the first reference).
        const references = [
            fullStaff?.faceReferenceImage, fullUser?.faceReferenceImage,
            fullStaff?.faceFirstImage, fullUser?.faceFirstImage,
            fullStaff?.avatar, fullUser?.avatar,
        ].filter((u) => typeof u === 'string' && u.startsWith('http'));
        const uniqueReferences = [...new Set(references)];

        if (uniqueReferences.length === 0) {
            // FIRST PUNCH with no prior photo to compare against → trust-on-first-use:
            // store this live embedding as the canonical enrollment so EVERY later
            // check (EHRMS 1-to-1, EHRMS 1-to-many, face kiosk) validates against it.
            const enrolled = await persistFirstPunchEnrollment(staff?._id, liveEmbedding);
            return res.status(200).json({
                success: true,
                match: true,
                enrolled,
                message: enrolled
                    ? 'First punch enrolled. Future punches verify against this face.'
                    : 'First punch captured as your face reference.',
            });
        }

        // Try each reference until one matches. Track the best (smallest) distance so
        // a near-miss is visible in logs for threshold tuning.
        let matched = false;
        let bestDistance = null;
        let lastError = null;
        for (const referenceUrl of uniqueReferences) {
            let result;
            // In-process dlib engine (spawned worker) — no external service/port.
            try {
                result = await faceEngine.verify({ selfie, referenceUrl });
            } catch (e) {
                console.warn('[verifyFace] face engine error:', e?.message);
                result = { match: false, error: 'Face verification failed. Please try again.' };
            }
            if (typeof result.distance === 'number') {
                bestDistance = bestDistance == null ? result.distance : Math.min(bestDistance, result.distance);
            }
            if (result.error) lastError = result.error;
            if (result.match) { matched = true; break; }
        }

        console.log(`[verifyFace] staff=${staff?._id || user?._id} refs=${uniqueReferences.length} matched=${matched} bestDistance=${bestDistance}`);

        const userMessage = matched ? 'Photo matched' : toUserFriendlyVerifyMessage(lastError);
        // A returning user just validated against their OWN profile photo → promote
        // that verified live embedding to the canonical enrollment (first-punch enroll),
        // so subsequent punches use the fast 1-to-1 embedding path and the kiosk/1-to-many
        // recognise them off the same embedding.
        let nowEnrolled = false;
        if (matched) {
            nowEnrolled = await persistFirstPunchEnrollment(staff?._id, liveEmbedding);
        }
        return res.status(200).json({
            success: true,
            match: matched,
            enrolled: nowEnrolled,
            message: userMessage
        });
    } catch (error) {
        console.error('verifyFace Error:', error);
        return res.status(500).json({
            success: false,
            match: false,
            error: { message: 'Face verification failed. Please try again.' }
        });
    }
};

function toUserFriendlyVerifyMessage(raw) {
    if (!raw || typeof raw !== 'string') return 'Face not matching. Please try again.';
    const s = raw.toLowerCase();
    // Pass through the face-attendance app's actionable kiosk-guard / liveness
    // messages verbatim — they tell the user exactly how to fix the capture.
    if (s.includes('too far') || s.includes('too close') || s.includes('off-center')
        || s.includes('multiple faces') || s.includes('only one person')
        || s.includes('spoof') || s.includes('look straight') || s.includes('blurry')) {
        return raw;
    }
    if (s.includes('no face') || s.includes('face could not be detected')) return 'No face detected. Please ensure your face is clearly visible.';
    if (s.includes('no profile') || s.includes('upload a profile')) return 'Please upload a profile photo first.';
    if (s.includes('not available') || s.includes('verification failed') || s.includes('exception') || s.includes('error')) return 'Face verification failed. Please try again.';
    if (s.includes('prepare images') || s.includes('could not')) return 'Could not verify. Please try again.';
    return 'Face not matching. Please try again.';
}

// ENROLLMENT does NOT do identity matching — it only captures + saves the face
// embedding. So its failures must NEVER say "verification failed" (that wording is
// for the punch-time 1-to-1 check). Map the engine/embed error to an enrollment-
// accurate, actionable message: retake (face not seen) vs. service-warming-up.
function toUserFriendlyEnrollMessage(raw) {
    if (!raw || typeof raw !== 'string') return 'Could not register your face. Please try again.';
    const s = raw.toLowerCase();
    // Backend engine not ready (missing python deps like cv2/numpy, worker crash,
    // service unavailable). This is NOT user-fixable, so never blame lighting/framing.
    if (s.includes('no module') || s.includes('cv2') || s.includes('numpy')
        || s.includes('worker') || s.includes('not available') || s.includes('unavailable')
        || s.includes('engine') || s.includes('timeout') || s.includes('timed out')
        || s.includes('crash') || s.includes('exception')) {
        return 'Face service isn\'t ready yet. Please try again in a moment.';
    }
    // Blurry capture — pass the engine's actionable wording through verbatim so the
    // user knows to hold steady / improve lighting rather than re-framing.
    if (s.includes('blurry')) return raw;
    // Genuine capture problem — guide framing only (no lighting wording per request).
    if (s.includes('no face') || s.includes('could not be detected') || s.includes('detect')) {
        return 'We couldn\'t see your face clearly. Fit your face inside the oval and try again.';
    }
    return 'Could not register your face. Please try again.';
}

/**
 * GET /auth/check-active (protected)
 * Returns { active: boolean } for current staff. Used by app to poll every 5s; if active is false (deactivated), app logs out silently.
 */
const checkActive = async (req, res) => {
    try {
        const staffId = req.staff?._id;
        if (!staffId) {
            return res.status(401).json({ success: false, active: false });
        }
        const staff = await Staff.findById(staffId).select('status').lean();
        const active = staff && (staff.status || '').toString().toLowerCase() !== 'deactivated';
        return res.json({ success: true, active: !!active });
    } catch (err) {
        console.error('[authController] checkActive:', err.message);
        return res.status(500).json({ success: false, active: false });
    }
};

/**
 * POST /auth/enroll-face (protected)
 * One-time face enrollment. Body: { selfies: ["data:image/...;base64,...", ...] }
 * (or a single { selfie }). Each image is embedded by the face service; the 128-D
 * samples are stored on the Staff doc and used as the FIXED reference for every
 * future punch (no rolling drift). Re-calling replaces the prior enrollment.
 */
const enrollFace = async (req, res) => {
    try {
        const staff = req.staff;
        if (!staff || !staff._id) {
            return res.status(400).json({ success: false, message: 'No staff profile to enroll.' });
        }
        const body = req.body || {};
        const list = Array.isArray(body.selfies) ? body.selfies : (body.selfie ? [body.selfie] : []);
        const images = list.filter((s) => typeof s === 'string' && s.length > 0);
        if (images.length === 0) {
            return res.status(400).json({ success: false, message: 'At least one selfie is required to enroll.' });
        }

        const embeddings = [];
        let lastError = null;
        for (const img of images) {
            try {
                const r = await faceEngine.embed(img);
                if (Array.isArray(r.embedding)) embeddings.push(r.embedding);
                else if (r.error) lastError = r.error;
            } catch (e) {
                console.warn('[enrollFace] embed engine error:', e?.message);
                return res.status(503).json({ success: false, message: 'The face service is starting up. Please wait a moment and try again.' });
            }
        }
        if (embeddings.length === 0) {
            // Enrollment only embeds + saves — never say "verification failed" here.
            console.warn('[enrollFace] no embedding extracted; lastError=', lastError);
            return res.status(200).json({
                success: false,
                message: toUserFriendlyEnrollMessage(lastError || 'No face detected'),
            });
        }

        // ── Duplicate-face guard ────────────────────────────────────────────────
        // Stop ONE person from enrolling against MULTIPLE employee logins
        // (buddy-enroll). Compare the freshly captured embedding(s) against every
        // OTHER enrolled staff in the same business; if this face already matches
        // someone else within the same-person threshold, refuse the enrollment.
        // The 128-D dlib descriptors are comparable regardless of which path stored
        // them (lenient enroll vs strict first-punch), same as identifyFromEnrollments.
        // Scoped to the business so the same person can legitimately exist per tenant.
        // Fails open on a DB error (logged) so an infra blip can't lock out enrollment.
        try {
            const scope = staff.businessId ? { businessId: staff.businessId } : {};
            const others = await Staff.find({
                ...scope,
                _id: { $ne: staff._id },
                faceEnrollEmbeddings: { $exists: true, $ne: [] },
            }).select('_id employeeId name faceEnrollEmbeddings').lean();

            let clash = null;
            for (const other of others) {
                const samples = Array.isArray(other.faceEnrollEmbeddings) ? other.faceEnrollEmbeddings : [];
                for (const emb of samples) {
                    for (const fresh of embeddings) {
                        const d = euclideanDistance(fresh, emb);
                        if (d <= FACE_MATCH_THRESHOLD && (clash === null || d < clash.distance)) {
                            clash = { staff: other, distance: d };
                        }
                    }
                }
            }
            if (clash) {
                console.warn(`[enrollFace] duplicate face: staff=${staff._id} matches staff=${clash.staff._id} (${clash.staff.name}) distance=${clash.distance.toFixed(3)}`);
                return res.status(409).json({
                    success: false,
                    message: `This face is already registered to another employee${clash.staff.name ? ` (${clash.staff.name})` : ''}. A face can only be enrolled for one employee.`,
                });
            }
        } catch (e) {
            console.warn('[enrollFace] duplicate-face check failed (allowing enrollment):', e?.message);
        }

        // Use the first enrollment selfie as the user's PROFILE PHOTO (avatar). Upload
        // it to storage and point both Staff.avatar and User.avatar at it, so the
        // registered face is the profile photo everywhere.
        let photoUrl = null;
        try {
            let b64 = String(images[0]);
            if (b64.startsWith('data:image')) b64 = b64.replace(/^data:image\/\w+;base64,/, '');
            const buffer = Buffer.from(b64, 'base64');
            if (buffer && buffer.length > 0) {
                const companyId = staff?.businessId ? String(staff.businessId) : undefined;
                const employeeName = staff?.name || req.user?.name;
                const up = await digitalOceanService.uploadImage(buffer, undefined, {
                    req, companyId, employeeName,
                    category: 'employees', subfolder: 'avatar', format: 'jpg',
                });
                if (up?.success) photoUrl = up.url;
            }
        } catch (e) {
            console.warn('[enrollFace] avatar upload failed (keeping enrollment):', e?.message);
        }

        const staffUpdate = {
            faceEnrollEmbeddings: embeddings,
            faceEnrolledAt: new Date(),
        };
        if (photoUrl) {
            staffUpdate.avatar = photoUrl;
            staffUpdate.faceEnrollImage = photoUrl;
        }
        await Staff.findByIdAndUpdate(staff._id, staffUpdate);
        if (photoUrl && req.user?._id) {
            await User.findByIdAndUpdate(req.user._id, { avatar: photoUrl });
        }
        console.log(`[enrollFace] staff=${staff._id} enrolled samples=${embeddings.length} avatar=${photoUrl ? 'updated' : 'unchanged'}`);
        return res.status(200).json({
            success: true,
            samples: embeddings.length,
            avatar: photoUrl,
            message: 'Face enrolled successfully.',
        });
    } catch (error) {
        console.error('enrollFace Error:', error);
        return res.status(500).json({ success: false, message: 'Enrollment failed. Please try again.' });
    }
};

/**
 * GET /auth/face-enroll-status (protected)
 * Returns whether the current staff has registered their face, so the app can
 * prompt enrollment before the first punch.
 */
const getFaceEnrollStatus = async (req, res) => {
    try {
        const staff = req.staff;
        if (!staff || !staff._id) return res.json({ success: true, enrolled: false, samples: 0 });
        const s = await Staff.findById(staff._id).select('faceEnrollEmbeddings faceEnrolledAt').lean();
        const samples = Array.isArray(s?.faceEnrollEmbeddings) ? s.faceEnrollEmbeddings.length : 0;
        return res.json({ success: true, enrolled: samples > 0, samples, enrolledAt: s?.faceEnrolledAt || null });
    } catch (error) {
        console.error('[authController] getFaceEnrollStatus:', error.message);
        return res.status(500).json({ success: false, enrolled: false });
    }
};

/**
 * Auto-enrollment on FIRST PUNCH. Persists the live (strict embedLive) embedding as
 * the user's canonical Staff.faceEnrollEmbeddings — the SAME store the 1-to-1 path,
 * the 1-to-many guard, and the face-app kiosk all validate against. So a user never
 * needs a separate enroll step: their first successful punch registers the face, and
 * every later punch/break (in either app) is checked against that one embedding.
 *
 * Trust-on-first-use: the punch is already authenticated as this staff. Returning
 * users with a profile photo are validated against it BEFORE this runs (see caller),
 * so a wrong face can't hijack an account that already has a reference image.
 */
async function persistFirstPunchEnrollment(staffId, embedding) {
    if (!staffId || !Array.isArray(embedding) || embedding.length === 0) return false;
    try {
        await Staff.findByIdAndUpdate(staffId, {
            faceEnrollEmbeddings: [embedding],
            faceEnrolledAt: new Date(),
        });
        console.log(`[verifyFace] first-punch auto-enrolled staff=${staffId} (1 sample)`);
        return true;
    } catch (e) {
        console.warn('[verifyFace] first-punch auto-enroll failed (punch still allowed):', e?.message);
        return false;
    }
}

/**
 * CANONICAL 1-to-many matcher — the single source of identity for BOTH apps.
 *
 * Embeds the live selfie with the STRICT engine (faceEngine.embedLive: kiosk
 * guards + anti-spoof) and finds the closest enrolled Staff across [scopeFilter],
 * comparing against Staff.faceEnrollEmbeddings — the SAME enrollment used by the
 * 1-to-1 verifyFace path. This is what makes one enrollment validate both 1-to-1
 * and 1-to-many: the EHRMS app's cross-user guard (verifyIdentity) and the
 * face-app kiosk (identifyFace) both call it.
 *
 * Returns { ok, error?, liveError?, best: {staff, distance}|null, candidates }.
 */
async function identifyFromEnrollments(selfie, scopeFilter = {}) {
    let liveEmbedding = null;
    let liveError = null;
    try {
        const r = await faceEngine.embedLive(selfie);
        liveEmbedding = r.embedding;
        liveError = r.error || null;
    } catch (e) {
        console.warn('[identifyFromEnrollments] engine unavailable:', e?.message);
        return { ok: false, error: 'engine_unavailable', best: null, candidates: 0 };
    }
    if (!Array.isArray(liveEmbedding)) {
        return { ok: true, liveError: liveError || 'No face detected', best: null, candidates: 0 };
    }

    const filter = { ...scopeFilter, faceEnrollEmbeddings: { $exists: true, $ne: [] } };
    const staffList = await Staff.find(filter)
        .select('_id userId employeeId name email businessId faceEnrollEmbeddings').lean();

    // Track the closest AND second-closest (different) person so the caller can
    // require a margin between them — an ambiguous near-tie is rejected rather than
    // assigned to whichever enrolled face is marginally closer.
    let best = null;
    let second = null;
    for (const s of staffList) {
        const samples = Array.isArray(s.faceEnrollEmbeddings) ? s.faceEnrollEmbeddings : [];
        let bestForStaff = Infinity;
        for (const emb of samples) {
            const d = euclideanDistance(liveEmbedding, emb);
            if (d < bestForStaff) bestForStaff = d;
        }
        const cand = { staff: s, distance: bestForStaff };
        if (best === null || bestForStaff < best.distance) {
            second = best;
            best = cand;
        } else if (second === null || bestForStaff < second.distance) {
            second = cand;
        }
    }
    return { ok: true, best, second, candidates: staffList.length };
}

/**
 * POST /attendance/verify-identity (protected) — EHRMS app's cross-user (anti
 * buddy-punch) guard. 1-to-many over the canonical Staff.faceEnrollEmbeddings,
 * scoped to the claimer's company. The claimer is the AUTHENTICATED staff (not a
 * spoofable body field). Response shape matches what FaceIdentityGuard expects:
 *   { verified, reason, matched_employee_id?, matched_name?, confidence }
 *   reason: 'match' | 'identity_mismatch' | 'not_recognized' | 'no_face'
 *           | 'claimer_not_enrolled' | 'error'
 * Always 200 so the app's fail-open guard treats inconclusive reasons as allow.
 */
const verifyIdentity = async (req, res) => {
    try {
        const selfie = req.body?.image_base64 || req.body?.selfie;
        if (!selfie || typeof selfie !== 'string') {
            return res.status(400).json({ verified: false, reason: 'no_image' });
        }
        const staff = req.staff;
        if (!staff || !staff._id) {
            return res.status(200).json({ verified: false, reason: 'claimer_not_enrolled', confidence: 0 });
        }
        const claimer = await Staff.findById(staff._id)
            .select('_id employeeId name businessId faceEnrollEmbeddings').lean();
        const claimerEnrolled = Array.isArray(claimer?.faceEnrollEmbeddings) && claimer.faceEnrollEmbeddings.length > 0;
        if (!claimerEnrolled) {
            // Nothing canonical to match the logged-in user against → can't do a
            // cross-user check. Inconclusive → app allows (1-to-1 verifyFace still gates).
            return res.status(200).json({ verified: false, reason: 'claimer_not_enrolled', confidence: 0 });
        }

        const scope = claimer.businessId ? { businessId: claimer.businessId } : {};
        const r = await identifyFromEnrollments(selfie, scope);
        if (!r.ok) return res.status(200).json({ verified: false, reason: 'error' });
        if (!r.best) {
            return res.status(200).json({ verified: false, reason: 'no_face', detail: r.liveError });
        }

        const confidence = Math.round((1 - r.best.distance) * 1000) / 10;
        // Strict 1-to-many gate: close enough AND unambiguously separated from the
        // next-closest person. An ambiguous/loose best match is NOT a recognition.
        if (!isConfidentIdentification(r.best, r.second)) {
            return res.status(200).json({ verified: false, reason: 'not_recognized', confidence });
        }
        const isClaimer = String(r.best.staff._id) === String(claimer._id);
        if (isClaimer) {
            return res.status(200).json({
                verified: true, reason: 'match',
                matched_employee_id: r.best.staff.employeeId, matched_name: r.best.staff.name, confidence,
            });
        }
        // Best match is a DIFFERENT enrolled employee → impersonation / buddy punch.
        return res.status(200).json({
            verified: false, reason: 'identity_mismatch',
            matched_employee_id: r.best.staff.employeeId, matched_name: r.best.staff.name, confidence,
        });
    } catch (e) {
        console.error('[verifyIdentity]', e.message);
        return res.status(200).json({ verified: false, reason: 'error' });
    }
};

/**
 * POST /attendance/identify-face (kiosk secret) — pure 1-to-many identify for the
 * face-app KIOSK, against the SAME canonical Staff.faceEnrollEmbeddings. Lets the
 * face kiosk recognize a person off EHRMS's enrollment instead of its own store,
 * so both apps validate one enrollment. Auth is a shared header (x-face-kiosk-secret)
 * — the kiosk is not a logged-in staff. Returns:
 *   { matched, employee_id?, employee_name?, email?, confidence, reason? }
 */
const identifyFace = async (req, res) => {
    try {
        const selfie = req.body?.image_base64 || req.body?.selfie;
        if (!selfie || typeof selfie !== 'string') {
            return res.status(400).json({ matched: false, reason: 'no_image' });
        }
        const scope = {};
        if (req.body?.business_id) scope.businessId = req.body.business_id;
        const r = await identifyFromEnrollments(selfie, scope);
        if (!r.ok) return res.status(200).json({ matched: false, reason: 'engine_unavailable' });
        if (!r.best) return res.status(200).json({ matched: false, reason: 'no_face', detail: r.liveError });

        const confidence = Math.round((1 - r.best.distance) * 1000) / 10;
        // Strict 1-to-many gate (see isConfidentIdentification): a brand-new,
        // unenrolled person must come back NOT recognized so the kiosk shows the
        // "Enroll Your Face" prompt — never get assigned to whichever enrolled face
        // happens to be marginally closest (which also flips between people across
        // the 800ms scan frames).
        if (!isConfidentIdentification(r.best, r.second)) {
            const ambiguous = r.second && (r.second.distance - r.best.distance) < FACE_IDENTIFY_MARGIN
                && r.best.distance <= FACE_IDENTIFY_THRESHOLD;
            console.warn(`[identifyFace] not recognized: best=${r.best.distance.toFixed(3)}`
                + (r.second ? ` second=${r.second.distance.toFixed(3)}` : ' (only candidate)')
                + ` candidates=${r.candidates}${ambiguous ? ' [ambiguous near-tie]' : ''}`);
            return res.status(200).json({ matched: false, reason: 'not_recognized', confidence });
        }

        // Mint a SHORT-LIVED EHRMS token for the matched employee so the face kiosk can
        // punch on their behalf WITHOUT any per-employee "linking" / stored credentials.
        // A recognized face (against the canonical Staff.faceEnrollEmbeddings) IS the
        // authorization; the kiosk shared-secret gates the endpoint. Short expiry keeps
        // the exposure tiny vs. the old design that stored long-lived tokens in the face DB.
        // protect() accepts a token whose `id` is the User._id (falls back to Staff._id).
        const secret = process.env.JWT_SECRET || 'secret';
        const tokenId = r.best.staff.userId || r.best.staff._id;
        const accessToken = jwt.sign({ id: tokenId }, secret, { expiresIn: '30m' });
        const refreshToken = jwt.sign({ id: tokenId }, secret, { expiresIn: '12h' });

        return res.status(200).json({
            matched: true,
            employee_id: r.best.staff.employeeId,
            employee_name: r.best.staff.name,
            email: r.best.staff.email,
            confidence,
            // Token the kiosk uses to punch/break against EHRMS directly (no linking).
            access_token: accessToken,
            refresh_token: refreshToken,
        });
    } catch (e) {
        console.error('[identifyFace]', e.message);
        return res.status(500).json({ matched: false, reason: 'error', detail: e.message });
    }
};

/**
 * GET /attendance/kiosk-enrolled (kiosk secret) — list of employees ENROLLED in EHRMS
 * (Staff.faceEnrollEmbeddings non-empty), for the face-app dashboard. Profile summary
 * only; full detail (attendance + month) comes from kioskEmployeeDetail on tap.
 */
const kioskEnrolledList = async (req, res) => {
    try {
        const filter = { faceEnrollEmbeddings: { $exists: true, $ne: [] } };
        if (req.query.business_id) filter.businessId = req.query.business_id;
        const staff = await Staff.find(filter)
            .select('employeeId name email department designation avatar faceEnrolledAt status')
            .sort({ name: 1 }).lean();

        // Today's attendance for every enrolled employee in ONE query — drives the
        // dashboard's per-day, user-wise Present/Late/On-Break/Permission summary.
        const staffIds = staff.map((s) => s._id);
        const now = new Date();
        const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const tomorrow = new Date(todayStart); tomorrow.setDate(todayStart.getDate() + 1);
        let todayAtt = [];
        try {
            todayAtt = await Attendance.find({
                $or: [{ employeeId: { $in: staffIds } }, { user: { $in: staffIds } }],
                date: { $gte: todayStart, $lt: tomorrow },
            }).select('employeeId user punchIn punchOut status lateMinutes permissionConsumedMinutes permissionApprovedMinutes break.breaks').lean();
        } catch (e) {
            console.error('[kioskEnrolledList] today attendance lookup failed:', e.message);
        }
        // Map staff _id -> today's attendance doc.
        const attByStaff = new Map();
        for (const a of todayAtt) {
            const key = String(a.employeeId || a.user || '');
            if (key) attByStaff.set(key, a);
        }
        // A break is ongoing when it has started but not yet ended.
        const isOnBreak = (a) => Array.isArray(a?.break?.breaks)
            && a.break.breaks.some((b) => b && b.startTime && !b.endTime);

        let presentToday = 0, lateToday = 0, onBreakToday = 0, permissionToday = 0;
        const employees = staff.map((s) => {
            const a = attByStaff.get(String(s._id));
            const present = !!(a && a.punchIn);
            const late = !!(a && Number(a.lateMinutes) > 0);
            const onBreak = isOnBreak(a);
            const permission = !!(a && (Number(a.permissionConsumedMinutes) > 0 || Number(a.permissionApprovedMinutes) > 0));
            if (present) presentToday++;
            if (late) lateToday++;
            if (onBreak) onBreakToday++;
            if (permission) permissionToday++;
            return {
                employee_id: s.employeeId,
                name: s.name,
                email: s.email || null,
                department: s.department || null,
                designation: s.designation || null,
                avatar: s.avatar || null,
                enrolled_at: s.faceEnrolledAt || null,
                status: s.status || null,
                // Today's live attendance snapshot (per-user).
                present_today: present,
                late_today: late,
                on_break: onBreak,
                permission_today: permission,
                today_status: a ? (a.status || null) : null,
            };
        });

        return res.json({
            count: staff.length,
            // Per-day, user-wise tallies for the dashboard summary card.
            present_today: presentToday,
            late_today: lateToday,
            on_break_today: onBreakToday,
            permission_today: permissionToday,
            employees,
        });
    } catch (e) {
        console.error('[kioskEnrolledList]', e.message);
        return res.status(500).json({ employees: [], error: 'Failed to load enrolled employees.' });
    }
};

/**
 * GET /attendance/kiosk-employee/:employeeId (kiosk secret) — full detail for one
 * enrolled employee: profile + today's attendance + this month's attendance rows.
 */
const kioskEmployeeDetail = async (req, res) => {
    try {
        const employeeId = req.params.employeeId || req.query.employee_id;
        if (!employeeId) return res.status(400).json({ error: 'employee_id required' });
        const s = await Staff.findOne({ employeeId })
            .select('employeeId name email phone alternativePhone designation department staffType role shiftName status joiningDate avatar gender dob bloodGroup faceEnrolledAt')
            .lean();
        if (!s) return res.status(404).json({ error: 'Employee not found' });

        const now = new Date();
        const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const tomorrow = new Date(todayStart); tomorrow.setDate(todayStart.getDate() + 1);
        const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
        const endOfMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59, 999);
        const byStaff = { $or: [{ employeeId: s._id }, { user: s._id }] };

        const [todayAtt, monthAtt] = await Promise.all([
            Attendance.findOne({ ...byStaff, date: { $gte: todayStart, $lt: tomorrow } }).lean(),
            Attendance.find({ ...byStaff, date: { $gte: startOfMonth, $lte: endOfMonth } }).sort({ date: 1 }).lean(),
        ]);

        const brkMin = (a) => a.break ? Math.round((a.break.totalBreakSeconds || 0) / 60) || (a.break.totalBreakMin || 0) : 0;
        const brkFine = (a) => a.break ? (a.break.totalBreakFineAmount || 0) : 0;
        // attendance.fineAmount is now the GRAND total (late + early + permission + break).
        // Report `fine` as the NON-break portion so break_fine + fine stay disjoint and
        // their sum equals the grand total — no double counting on the kiosk.
        const nonBreakFine = (a) => Math.max(0, (typeof a.fineAmount === 'number' ? a.fineAmount : 0) - brkFine(a));
        const round2 = (n) => Math.round(n * 100) / 100;
        // Per-break sessions for the expandable day card (start/end/duration/fine).
        const breakSessions = (a) => (a.break && Array.isArray(a.break.breaks) ? a.break.breaks : [])
            .filter((b) => b && (b.startTime || b.endTime || b.duration))
            .map((b) => ({
                start: b.startTime || null,
                end: b.endTime || null,
                duration_min: Math.round(b.duration || 0),
                fine_min: b.breakFineMins || 0,
                fine: round2(b.breakFineAmount || 0),
            }));
        // Permission usage + fine for the day (custom-time step-outs / late-in / early-out).
        const permission = (a) => ({
            consumed_min: a.permissionConsumedMinutes || 0,
            approved_min: a.permissionApprovedMinutes || 0,
            remaining_min: a.permissionRemainingMinutes || 0,
            late_min: a.permissionLateMinutes || 0,
            early_min: a.permissionEarlyMinutes || 0,
            // Fined permission minutes (over-allowance exceed + custom-window overrun).
            fine_min: (a.permissionFineMinutes || 0) + (a.permissionOverrunMinutes || 0),
            fine_amount: round2((a.permissionFineAmount || 0) + (a.permissionOverrunFineAmount || 0)),
        });
        const fmt = (a) => a ? {
            date: a.date,
            punch_in: a.punchIn || null,
            punch_out: a.punchOut || null,
            status: a.status || null,
            work_hours: typeof a.workHours === 'number' ? a.workHours : null,
            // Daily breaks taken + fines.
            break_min: brkMin(a),
            break_count: a.break ? (a.break.totalBreakCount || 0) : 0,
            break_fine: brkFine(a),
            break_fine_min: a.break ? (a.break.totalBreakFineMins || 0) : 0,
            late_min: typeof a.lateMinutes === 'number' ? a.lateMinutes : 0,
            early_min: typeof a.earlyMinutes === 'number' ? a.earlyMinutes : 0,
            // Non-break fine (late + early + permission). Grand total = break_fine + fine.
            fine: nonBreakFine(a),
            // Grand total fine for the day (matches attendance.fineAmount).
            total_fine: typeof a.fineAmount === 'number' ? a.fineAmount : 0,
            // Detail rows surfaced when the day card is expanded on the kiosk.
            breaks: breakSessions(a),
            permission: permission(a),
        } : null;

        const sum = (f) => monthAtt.reduce((t, a) => t + (f(a) || 0), 0);

        return res.json({
            profile: {
                employee_id: s.employeeId, name: s.name, email: s.email || null,
                phone: s.phone || s.alternativePhone || null,
                designation: s.designation || null, department: s.department || null,
                staff_type: s.staffType || null, role: s.role || null, shift: s.shiftName || null,
                status: s.status || null, joining_date: s.joiningDate || null, avatar: s.avatar || null,
                gender: s.gender || null, dob: s.dob || null, blood_group: s.bloodGroup || null,
                enrolled_at: s.faceEnrolledAt || null,
            },
            today: fmt(todayAtt),
            month: monthAtt.map(fmt),
            present_days: monthAtt.filter((a) => a.punchIn).length,
            month_label: now.toLocaleString('en-US', { month: 'long', year: 'numeric' }),
            // Month-to-date totals for breaks taken + fines.
            totals: {
                break_min: sum((a) => brkMin(a)),
                break_count: sum((a) => a.break && a.break.totalBreakCount),
                break_fine: round2(sum((a) => a.break && a.break.totalBreakFineAmount)),
                // Non-break fine so break_fine + fine = total_fine (no double count).
                fine: round2(sum((a) => nonBreakFine(a))),
                total_fine: round2(sum((a) => a.fineAmount)),
            },
        });
    } catch (e) {
        console.error('[kioskEmployeeDetail]', e.message);
        return res.status(500).json({ error: 'Failed to load employee detail.' });
    }
};

/**
 * POST /attendance/kiosk-clear-face (kiosk secret) — wipe a staff member's canonical
 * face enrollment so they can (re-)enroll a fresh face. Lets the face-app ADMIN clear
 * an enrolled face from the kiosk without a per-staff login. Looked up by employee_id
 * (external HR id) or email. Clearing faceEnrollEmbeddings drops them out of BOTH the
 * 1-to-1 verify and the 1-to-many identify until they enroll again.
 * Body: { employee_id? , email? }. Returns { success, employee_id, name, cleared }.
 */
const kioskClearFace = async (req, res) => {
    try {
        const employeeId = req.body?.employee_id || req.body?.employeeId;
        const email = req.body?.email;
        if (!employeeId && !email) {
            return res.status(400).json({ success: false, message: 'employee_id or email is required.' });
        }
        // Match by employeeId AND/OR email. employeeId is NOT guaranteed unique in the
        // data, so a findOne() could clear a DIFFERENT same-id record and leave the one
        // shown on the kiosk still enrolled (the reported "cleared but still showing"
        // bug). Match ALL candidates and clear every one, so the displayed record is
        // always among them. Email (when provided) disambiguates duplicate ids.
        const esc = (s) => String(s).trim().replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        const or = [];
        if (employeeId) or.push({ employeeId });
        if (email) or.push({ email: new RegExp(`^${esc(email)}$`, 'i') });
        const matches = await Staff.find({ $or: or }).select('_id userId employeeId name faceEnrollEmbeddings');
        if (!matches.length) {
            return res.status(404).json({ success: false, message: 'No enrolled employee found for that id/email.' });
        }
        // Clearing enrollment also removes the PROFILE IMAGE: enroll-face set the avatar
        // FROM the enrollment selfie (Staff.avatar + Staff.faceEnrollImage + User.avatar),
        // so a clear must wipe all three — otherwise the cleared person still shows their
        // enrolled face as their profile photo on the kiosk roster/detail.
        let cleared = 0;
        for (const staff of matches) {
            cleared += Array.isArray(staff.faceEnrollEmbeddings) ? staff.faceEnrollEmbeddings.length : 0;
            await Staff.findByIdAndUpdate(staff._id, {
                faceEnrollEmbeddings: [],
                faceEnrolledAt: null,
                faceEnrollImage: null,
                avatar: null,
            });
            if (staff.userId) {
                await User.findByIdAndUpdate(staff.userId, { avatar: null }).catch(() => {});
            }
        }
        console.log(`[kioskClearFace] cleared ${matches.length} record(s) for id=${employeeId || '-'} email=${email || '-'} samples=${cleared} + profile image`);
        return res.json({
            success: true,
            employee_id: matches[0].employeeId,
            name: matches[0].name,
            cleared,
            records: matches.length,
        });
    } catch (e) {
        console.error('[kioskClearFace]', e.message);
        return res.status(500).json({ success: false, message: 'Could not clear enrolled face.' });
    }
};

module.exports = {
    login,
    kioskAdminLogin,
    googleLogin,
    refreshAccessToken,
    register,
    getProfile,
    updateProfile,
    updateEducation,
    updateExperience,
    forgotPassword,
    verifyOTP,
    resetPassword,
    changePassword,
    updateProfilePhoto,
    verifyFace,
    enrollFace,
    getFaceEnrollStatus,
    verifyIdentity,
    identifyFace,
    kioskEnrolledList,
    kioskEmployeeDetail,
    kioskClearFace,
    checkActive
};
