/**
 * SendPulse email service (HTTPS API - no SMTP firewall issues).
 * Uses SENDPULSE_CLIENT_ID, SENDPULSE_CLIENT_SECRET, SENDPULSE_FROM_EMAIL, SENDPULSE_FROM_NAME.
 * Ref: backend/src/services/sendpulse.service.ts
 */
const https = require('https');

const API_URL = 'https://api.sendpulse.com';

let cachedToken = null;
let tokenExpiry = 0;

function request(method, path, body, accessToken = null) {
    return new Promise((resolve, reject) => {
        const url = new URL(path, API_URL);
        const opts = {
            hostname: url.hostname,
            path: url.pathname,
            method,
            headers: { 'Content-Type': 'application/json' }
        };
        if (accessToken) {
            opts.headers['Authorization'] = `Bearer ${accessToken}`;
        }
        const reqBody = body ? JSON.stringify(body) : undefined;
        if (reqBody) {
            opts.headers['Content-Length'] = Buffer.byteLength(reqBody);
        }

        const req = https.request(opts, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                try {
                    const parsed = data ? JSON.parse(data) : {};
                    if (res.statusCode >= 200 && res.statusCode < 300) {
                        resolve(parsed);
                    } else {
                        reject(new Error(parsed.message || parsed.error_description || data || `HTTP ${res.statusCode}`));
                    }
                } catch (e) {
                    reject(new Error(data || e.message));
                }
            });
        });
        req.on('error', reject);
        if (reqBody) req.write(reqBody);
        req.end();
    });
}

async function getAccessToken(clientId, clientSecret) {
    if (cachedToken && Date.now() < tokenExpiry) {
        return cachedToken;
    }
    const data = await request('POST', '/oauth/access_token', {
        grant_type: 'client_credentials',
        client_id: clientId,
        client_secret: clientSecret
    });
    if (!data.access_token) {
        throw new Error('SendPulse OAuth: no access_token in response');
    }
    cachedToken = data.access_token;
    const expiresIn = (data.expires_in || 3600) * 1000;
    tokenExpiry = Date.now() + expiresIn - 300000; // refresh 5 min before
    return cachedToken;
}

/**
 * Send email via SendPulse SMTP API
 * @param {string} toEmail
 * @param {string} subject
 * @param {string} html
 * @param {string} fromEmail - e.g. dev@askeva.io (must be verified in SendPulse)
 * @param {string} fromName - e.g. ASKEVA HRMS
 * @returns {Promise<{ success: boolean, error?: string, messageId?: string }>}
 */
async function sendEmail(toEmail, subject, html, fromEmail, fromName) {
    const clientId = process.env.SENDPULSE_CLIENT_ID;
    const clientSecret = process.env.SENDPULSE_CLIENT_SECRET;

    if (!clientId || !clientSecret) {
        return { success: false, error: 'SENDPULSE_CLIENT_ID and SENDPULSE_CLIENT_SECRET are required' };
    }
    if (!fromEmail) {
        return { success: false, error: 'SENDPULSE_FROM_EMAIL is required' };
    }

    try {
        const accessToken = await getAccessToken(clientId, clientSecret);
        const text = html.replace(/<[^>]*>/g, '').trim();

        const emailData = {
            email: {
                html: Buffer.from(html).toString('base64'),
                text,
                subject,
                from: { name: fromName || 'ASKEVA HRMS', email: fromEmail },
                to: [{ email: toEmail }]
            }
        };

        const response = await request('POST', '/smtp/emails', emailData, accessToken);
        const messageId = response.id || response.result?.id;
        return { success: true, messageId };
    } catch (error) {
        const message = error.message || 'SendPulse send failed';
        console.error('[SendPulseService] Failed to send:', message);
        return { success: false, error: message };
    }
}

module.exports = {
    sendEmail,
    getAccessToken
};
