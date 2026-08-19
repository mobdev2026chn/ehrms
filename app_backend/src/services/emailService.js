const nodemailer = require('nodemailer');
const sendpulseService = require('./sendpulseService');

// ETIMEDOUT = server cannot reach SMTP. Use SendPulse or SendGrid (HTTPS) on server.

const smtpConnectionTimeout = Number(process.env.EMAIL_CONNECTION_TIMEOUT) || 30000; // 30 seconds
const smtpGreetingTimeout = Number(process.env.EMAIL_GREETING_TIMEOUT) || 15000;
const smtpSocketTimeout = Number(process.env.EMAIL_SOCKET_TIMEOUT) || 30000;

const transporter = nodemailer.createTransport({
    host: process.env.EMAIL_HOST,
    port: Number(process.env.EMAIL_PORT) || 587,
    secure: process.env.EMAIL_SECURE === 'true',
    auth: {
        user: process.env.EMAIL_USER,
        pass: process.env.EMAIL_PASS
    },
    connectionTimeout: smtpConnectionTimeout,
    greetingTimeout: smtpGreetingTimeout,
    socketTimeout: smtpSocketTimeout,
    debug: process.env.EMAIL_DEBUG === 'true',
    logger: process.env.EMAIL_DEBUG === 'true'
});

// SendPulse (HTTPS) - preferred when SENDPULSE_CLIENT_ID + SENDPULSE_CLIENT_SECRET + SENDPULSE_FROM_EMAIL are set
const useSendPulse = !!(process.env.SENDPULSE_CLIENT_ID && process.env.SENDPULSE_CLIENT_SECRET && process.env.SENDPULSE_FROM_EMAIL);
if (useSendPulse) {
    console.log('[EmailService] SendPulse enabled. OTP emails will use SendPulse (SENDPULSE_FROM_EMAIL).');
}

// Optional: SendGrid (HTTPS) - use when SMTP is blocked and SendPulse not set
let sgMail = null;
if (process.env.SENDGRID_API_KEY) {
    try {
        sgMail = require('@sendgrid/mail');
        sgMail.setApiKey(process.env.SENDGRID_API_KEY);
        console.log('[EmailService] SendGrid API enabled (SENDGRID_API_KEY).');
    } catch (e) {
        console.warn('[EmailService] SENDGRID_API_KEY set but @sendgrid/mail not installed. Run: npm install @sendgrid/mail');
    }
}

// Verify SMTP transporter only when not using SendPulse or SendGrid
if (!useSendPulse && !process.env.SENDGRID_API_KEY && process.env.EMAIL_HOST && process.env.EMAIL_USER && process.env.EMAIL_PASS) {
    transporter.verify(function (error, success) {
        if (error) {
            console.error('[EmailService] ❌ SMTP verification failed:', error.message);
            console.error('[EmailService] If you see ETIMEDOUT: outbound SMTP may be blocked. Use SENDGRID_API_KEY or open firewall.');
        } else {
            console.log('[EmailService] ✅ SMTP transporter verified and ready');
        }
    });
} else if (!useSendPulse && !process.env.SENDGRID_API_KEY) {
    console.warn('[EmailService] ⚠️ No email config. Set SENDPULSE_* or SENDGRID_API_KEY or EMAIL_* for SMTP.');
}

/**
 * Build OTP email HTML based on type.
 * @param {string} otp
 * @param {'password-reset'|'two-factor-login'} type
 */
const OTP_HTML = (otp, type = 'password-reset') => {
    const isTwoFactor = type === 'two-factor-login';
    const title = isTwoFactor ? 'Two-Factor Authentication Login' : 'Password Reset Request';
    const intro = isTwoFactor
        ? 'You are attempting to login to your ASKEVA HRMS account with Two-Factor Authentication enabled.'
        : 'We received a request to reset the password for your ASKEVA HRMS account.';
    const footer = isTwoFactor
        ? 'If you did not attempt to login, please contact support immediately as your account may be compromised.'
        : 'If you did not request a password reset, you can safely ignore this email.';
    return `
    <div style="font-family: Arial, sans-serif; line-height: 1.6; color: #333;">
        <h2>${title}</h2>
        <p>${intro}</p>
        <p>Your One-Time Password (OTP) is:</p>
        <p style="font-size: 24px; font-weight: bold; letter-spacing: 4px;">${otp}</p>
        <p>This OTP is valid for <strong>10 minutes</strong>. Do not share it with anyone.</p>
        <p>${footer}</p>
        <br/>
        <p>Regards,<br/>ASKEVA HRMS Team</p>
    </div>
`;
};

/**
 * Send an OTP email for password reset or 2FA login.
 * @param {string} toEmail
 * @param {string} otp
 * @param {'password-reset'|'two-factor-login'} type
 */
const sendOTPEmail = async (toEmail, otp, type = 'password-reset') => {
    const normalizedTo = (toEmail && typeof toEmail === 'string')
        ? toEmail.trim().toLowerCase()
        : '';
    if (!normalizedTo || !otp) {
        console.error('[EmailService] ❌ Missing email or OTP');
        return { success: false, error: 'Email or OTP is missing' };
    }
    if (!normalizedTo.includes('@') || !normalizedTo.includes('.')) {
        console.error('[EmailService] ❌ Invalid email format');
        return { success: false, error: 'Invalid email address format' };
    }

    const fromEmail = process.env.SENDPULSE_FROM_EMAIL || process.env.EMAIL_FROM || process.env.EMAIL_USER;
    const fromName = process.env.SENDPULSE_FROM_NAME || process.env.EMAIL_FROM_NAME || 'ASKEVA HRMS';

    if (!fromEmail) {
        console.error('[EmailService] ❌ SENDPULSE_FROM_EMAIL or EMAIL_FROM or EMAIL_USER not set');
        return { success: false, error: 'Email configuration missing' };
    }

    const isTwoFactor = type === 'two-factor-login';
    const subject = isTwoFactor
        ? 'Two-Factor Authentication Login OTP - ASKEVA HRMS'
        : 'Your ASKEVA HRMS Password Reset OTP';
    const html = OTP_HTML(otp, type);

    // Prefer SendPulse when configured (HTTPS, no firewall issues)
    if (useSendPulse) {
        try {
            console.log(`[EmailService] Sending OTP via SendPulse to: ${normalizedTo} from: ${fromEmail}`);
            const result = await sendpulseService.sendEmail(normalizedTo, subject, html, fromEmail, fromName);
            if (result.success) {
                console.log(`[EmailService] ✅ OTP email sent via SendPulse to ${normalizedTo}`);
                return { success: true, messageId: result.messageId };
            }
            console.warn(`[EmailService] SendPulse failed, falling back to next provider. Error: ${result.error}`);
        } catch (error) {
            console.warn('[EmailService] SendPulse exception, falling back to next provider. Error:', error.message);
        }
    }

    // Fallback: SendGrid when API key is set
    if (sgMail) {
        try {
            console.log(`[EmailService] Sending OTP via SendGrid to: ${normalizedTo}`);
            await sgMail.send({ to: normalizedTo, from: { email: fromEmail, name: fromName }, subject, html });
            console.log(`[EmailService] ✅ OTP email sent via SendGrid to ${normalizedTo}`);
            return { success: true };
        } catch (error) {
            console.warn('[EmailService] SendGrid failed, falling back to SMTP. Error:', error.message);
        }
    }

    if (!transporter || !transporter.options || !transporter.options.auth) {
        console.error('[EmailService] ❌ SMTP not configured. Set EMAIL_HOST, EMAIL_USER, EMAIL_PASS or use SENDGRID_API_KEY');
        return { success: false, error: 'Email service not configured' };
    }

    const smtpFromEmail = process.env.EMAIL_FROM || process.env.EMAIL_USER;
    const mailOptions = {
        from: `"${fromName}" <${smtpFromEmail}>`,
        to: normalizedTo,
        subject,
        html
    };

    try {
        console.log(`[EmailService] Attempting to send OTP via SMTP to: ${normalizedTo}`);
        console.log(`[EmailService] SMTP Host: ${transporter.options.host} Port: ${transporter.options.port} (timeout: ${smtpConnectionTimeout}ms)`);

        const info = await transporter.sendMail(mailOptions);

        console.log(`[EmailService] ✅ OTP email sent via SMTP to ${normalizedTo}`);
        console.log(`[EmailService] Message ID: ${info.messageId}`);
        return { success: true, messageId: info.messageId, response: info.response };
    } catch (error) {
        console.error('[EmailService] ❌ SMTP failed:', error.message);
        console.error('[EmailService] Code:', error.code, 'Command:', error.command);
        if (error.code === 'ETIMEDOUT' || error.command === 'CONN') {
            console.error('[EmailService] Tip: Outbound SMTP may be blocked. Use SENDGRID_API_KEY (npm install @sendgrid/mail) or open firewall for SMTP port.');
        }
        return { success: false, error: error.message, code: error.code };
    }
};

/**
 * Send task OTP email with custom subject and HTML (uses SendPulse/SendGrid/SMTP).
 */
const sendTaskOtpEmail = async (toEmail, subject, html) => {
    if (!toEmail || !subject || !html) {
        return { success: false, error: 'Email, subject, and html are required' };
    }
    const fromEmail = process.env.SENDPULSE_FROM_EMAIL || process.env.EMAIL_FROM || process.env.EMAIL_USER;
    const fromName = process.env.SENDPULSE_FROM_NAME || process.env.EMAIL_FROM_NAME || 'ASKEVA HRMS';
    if (!fromEmail) {
        return { success: false, error: 'SENDPULSE_FROM_EMAIL or EMAIL_FROM not set' };
    }
    if (useSendPulse) {
        try {
            const result = await sendpulseService.sendEmail(toEmail, subject, html, fromEmail, fromName);
            if (result.success) return { success: true, messageId: result.messageId };
            console.warn('[EmailService] SendPulse failed, falling back to next provider. Error:', result.error);
        } catch (e) {
            console.warn('[EmailService] SendPulse exception, falling back to next provider. Error:', e.message);
        }
    }
    if (sgMail) {
        try {
            await sgMail.send({ to: toEmail, from: { email: fromEmail, name: fromName }, subject, html });
            return { success: true };
        } catch (e) {
            console.warn('[EmailService] SendGrid failed, falling back to SMTP. Error:', e.message);
        }
    }
    if (transporter?.options?.auth) {
        try {
            const smtpFrom = process.env.EMAIL_FROM || process.env.EMAIL_USER;
            await transporter.sendMail({
                from: `"${fromName}" <${smtpFrom}>`,
                to: toEmail,
                subject,
                html
            });
            return { success: true };
        } catch (e) {
            return { success: false, error: e.message };
        }
    }
    return { success: false, error: 'No email service configured (SENDPULSE_* or SENDGRID_API_KEY or EMAIL_*)' };
};

module.exports = {
    sendOTPEmail,
    sendTaskOtpEmail
};

