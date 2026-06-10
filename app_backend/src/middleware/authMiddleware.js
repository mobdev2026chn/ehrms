const jwt = require('jsonwebtoken');
const User = require('../models/User');
const Staff = require('../models/Staff');

const protect = async (req, res, next) => {
    let token;

    if (
        req.headers.authorization &&
        req.headers.authorization.startsWith('Bearer')
    ) {
        try {
            token = req.headers.authorization.split(' ')[1];

            // Sanitize token: Remove any surrounding quotes
            const rawToken = token;
            if (token.startsWith('"') || token.endsWith('"')) {
                token = token.replace(/^"|"$/g, '');
                console.log('DEBUG: AuthMiddleware - Token had quotes, sanitized');
            }

            console.log('DEBUG: AuthMiddleware - Raw token length:', rawToken.length);
            console.log('DEBUG: AuthMiddleware - Sanitized token length:', token.length);
            console.log('DEBUG: AuthMiddleware - Token preview:', token.substring(0, 20) + '...');

            // Ensure Secret matches Controller
            const secret = process.env.JWT_SECRET || 'secret';
            console.log('DEBUG: AuthMiddleware - Using secret source:', process.env.JWT_SECRET ? 'ENV' : 'DEFAULT');

            // Verify token
            console.log('DEBUG: AuthMiddleware - Verifying token...');
            const decoded = jwt.verify(token, secret);
            console.log('DEBUG: AuthMiddleware - Token decoded. ID:', decoded.id);

            // Try to find User first (Standard Backend Logic)
            let user = await User.findById(decoded.id).select('-password');
            let staff = null;

            if (user) {
                // Found User, now try to find associated Staff
                staff = await Staff.findOne({ userId: user._id });
                // If staff not found? Create temporary structure or allow just user? 
                // Creating a mock staff object or just proceeding with user is safer for now.
            } else {
                // Fallback: Token might contain Staff ID (Legacy App Logic)
                staff = await Staff.findById(decoded.id).select('-password');
                if (staff) {
                    user = await User.findById(staff.userId).select('-password');
                }
            }

            if (!user && !staff) {
                console.error('Auth Middleware: User/Staff not found for ID:', decoded.id);
                return res.status(401).json({ message: 'Not authorized, user not found' });
            }

            // Attach to req
            // Use unified structure: req.user = User, req.staff = Staff
            req.user = user || { _id: staff.userId, role: 'Employee' }; // Fallback user object
            req.staff = staff || { _id: user?._id }; // Fallback staff object (dangerous but prevents crashes)

            // Normalize Role
            if (req.user && !req.user.role && req.staff) req.user.role = 'Employee';

            // Should also attach businessId/companyId logic if needed
            req.companyId = user?.companyId || staff?.businessId;

            next();
        } catch (error) {
            console.error('Auth Middleware Verification Error:', error.message);
            // More descriptive error
            let msg = 'Not authorized, token failed';
            if (error.name === 'TokenExpiredError') {
                msg = 'Session expired, please login again';
            }
            res.status(401).json({ message: msg, error: error.message });
        }
    } else {
        res.status(401).json({ message: 'Not authorized, no token' });
    }
};

// Restrict a route to specific roles. Reads role from req.user (set by `protect`).
// Case-insensitive match; "Employee" fallback users are never admins.
const authorizeRoles = (...allowed) => {
    const allowedLc = allowed.map((r) => String(r).toLowerCase());
    return (req, res, next) => {
        const role = String(req.user?.role || req.staff?.role || '').toLowerCase();
        if (!role || !allowedLc.includes(role)) {
            return res.status(403).json({
                success: false,
                error: { message: 'Forbidden: requires one of [' + allowed.join(', ') + ']' }
            });
        }
        next();
    };
};

module.exports = { protect, authorizeRoles };