/**
 * Shared 429 handler for express-rate-limit.
 * Sends JSON body and sets Retry-After from req.rateLimit.resetTime when available.
 * Use with: rateLimit({ ..., handler: createRateLimitHandler('Too many requests...') })
 */
function createRateLimitHandler(message) {
    return function rateLimitHandler(req, res, next, optionsUsed) {
        if (res.headersSent) return;
        const info = req.rateLimit;
        if (info && info.resetTime) {
            const seconds = Math.ceil((new Date(info.resetTime) - Date.now()) / 1000);
            if (seconds > 0) {
                res.setHeader('Retry-After', Math.min(seconds, 120).toString());
            }
        } else if (optionsUsed && optionsUsed.windowMs) {
            res.setHeader('Retry-After', Math.min(Math.ceil(optionsUsed.windowMs / 1000), 120).toString());
        }
        res.status(429).json({
            success: false,
            error: { message: message || 'Too many requests. Please try again later.' }
        });
    };
}

module.exports = { createRateLimitHandler };
