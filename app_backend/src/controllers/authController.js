const User = require('../models/User');
const Staff = require('../models/Staff');
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
                        user = await User.findById(staff.userId);
                        user = await populateRoleIfPresent(user);
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
            avatar: staff?.avatar || user.avatar,
            locationAccess: staff?.locationAccess === true,
            taskSettings: taskSettings?.settings || null,
            branchName: staff?.branchId?.branchName ?? undefined,
        };

        // Create a refresh token (if needed by frontend, though Flutter usually uses access token for now)
        // For parity with Web Backend, we can generate one
        const refreshToken = jwt.sign({ id: user._id }, secret, { expiresIn: '7d' });

        // Set refresh token as httpOnly cookie (standard practice from Web Backend)
        res.cookie('refreshToken', refreshToken, {
            httpOnly: true,
            secure: process.env.NODE_ENV === 'production',
            sameSite: 'lax',
            maxAge: 7 * 24 * 60 * 60 * 1000, // 7 days
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
            avatar: staff?.avatar || user.avatar,
            locationAccess: staff?.locationAccess === true,
            taskSettings: taskSettings?.settings || null,
            branchName: staff?.branchId?.branchName ?? undefined,
        };

        res.json({
            success: true,
            data: {
                user: userResponse,
                accessToken
            }
        });

    } catch (error) {
        console.error(error);
        res.status(500).json({ success: false, error: { message: error.message } });
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
        // Always fetch latest avatar from DB so face matching uses only the current profile photo
        // (after user updates photo in profile, this returns the new URL; no cache)
        const fullUser = await User.findById(user._id).select('avatar').lean();
        let fullStaff = null;
        if (staff && staff._id) fullStaff = await Staff.findById(staff._id).select('avatar').lean();
        const profilePhotoUrl = fullUser?.avatar || fullStaff?.avatar;

        if (!profilePhotoUrl || !profilePhotoUrl.startsWith('http')) {
            return res.status(200).json({
                success: true,
                match: false,
                message: 'No profile photo uploaded. Please upload a profile photo first.'
            });
        }

        let selfiePath = null;
        let profilePath = null;
        const tmpDir = os.tmpdir();

        try {
            const base64Match = selfie.match(/^data:image\/\w+;base64,(.+)$/);
            const base64Data = base64Match ? base64Match[1] : selfie;
            const buf = Buffer.from(base64Data, 'base64');
            selfiePath = path.join(tmpDir, `selfie_${Date.now()}.jpg`);
            await fs.writeFile(selfiePath, buf);

            profilePath = path.join(tmpDir, `profile_${Date.now()}.jpg`);
            await new Promise((resolve, reject) => {
                const url = new URL(profilePhotoUrl);
                const client = url.protocol === 'https:' ? https : http;
                const req = client.get(profilePhotoUrl, (resp) => {
                    if (resp.statusCode !== 200) {
                        reject(new Error(`Profile photo fetch failed: ${resp.statusCode}`));
                        return;
                    }
                    const chunks = [];
                    resp.on('data', (c) => chunks.push(c));
                    resp.on('end', () => {
                        fs.writeFile(profilePath, Buffer.concat(chunks))
                            .then(resolve)
                            .catch(reject);
                    });
                });
                req.on('error', reject);
                req.setTimeout(15000, () => { req.destroy(); reject(new Error('Timeout')); });
            });
        } catch (e) {
            try {
                if (selfiePath) await fs.unlink(selfiePath).catch(() => {});
                if (profilePath) await fs.unlink(profilePath).catch(() => {});
            } catch (_) {}
            return res.status(200).json({
                success: true,
                match: false,
                message: 'Could not prepare images for verification.'
            });
        }

        const scriptDir = path.join(__dirname, '../../face_verify');
        const scriptPath = path.join(scriptDir, 'face_verify.py');
        const venvPythonWin = path.join(scriptDir, 'venv', 'Scripts', 'python.exe');
        const venvPythonUnix = path.join(scriptDir, 'venv', 'bin', 'python');
        const venvPython = process.platform === 'win32' ? venvPythonWin : venvPythonUnix;
        const py = require('fs').existsSync(venvPython) ? venvPython : (process.platform === 'win32' ? 'python' : 'python3');

        const result = await new Promise((resolve) => {
            const child = spawn(py, [scriptPath, selfiePath, profilePath], {
                cwd: scriptDir,
                timeout: 90000
            });
            let stdout = '';
            let stderr = '';
            child.stdout.on('data', (d) => { stdout += d.toString(); });
            child.stderr.on('data', (d) => { stderr += d.toString(); });
            child.on('error', () => resolve({ match: false, error: 'Face verification not available' }));
            child.on('close', (code) => {
                try {
                    const out = JSON.parse(stdout.trim() || '{}');
                    resolve({ match: !!out.match, error: out.error || null });
                } catch {
                    resolve({ match: false, error: stderr || 'Verification failed' });
                }
            });
        });

        try {
            if (selfiePath) await fs.unlink(selfiePath).catch(() => {});
            if (profilePath) await fs.unlink(profilePath).catch(() => {});
        } catch (_) {}

        // Map backend/script errors to clear user-facing message (no raw exceptions in app)
        const userMessage = result.match ? 'Photo matched' : toUserFriendlyVerifyMessage(result.error);

        return res.status(200).json({
            success: true,
            match: !!result.match,
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
    if (s.includes('no face') || s.includes('face could not be detected')) return 'No face detected. Please ensure your face is clearly visible.';
    if (s.includes('no profile') || s.includes('upload a profile')) return 'Please upload a profile photo first.';
    if (s.includes('not available') || s.includes('verification failed') || s.includes('exception') || s.includes('error')) return 'Face verification failed. Please try again.';
    if (s.includes('prepare images') || s.includes('could not')) return 'Could not verify. Please try again.';
    return 'Face not matching. Please try again.';
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

module.exports = {
    login,
    googleLogin,
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
    checkActive
};
