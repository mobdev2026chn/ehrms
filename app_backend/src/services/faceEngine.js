// In-process face engine for EHRMS — NO separate HTTP port.
//
// The Node backend spawns the Python face worker (face_verify/face_worker.py) as a
// persistent child process and talks to it over stdin/stdout (one JSON line each
// way), the same pattern the face-attendance app uses (aiEngine.js). This removes
// the old :5005 HTTP service: the dlib engine runs as a child of THIS process, so
// there is only one thing to run (the Node API on :9001).
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const FACE_VERIFY_DIR = path.join(__dirname, '..', '..', 'face_verify');
const WORKER_SCRIPT = path.join(FACE_VERIFY_DIR, 'face_worker.py');
// How long to wait for a single worker reply before giving up (keeps the queue
// from stalling forever if the child hangs).
const REQUEST_TIMEOUT_MS = 30000;

// Resolve a Python interpreter that has the dlib deps. Prefer FACE_PYTHON_BIN (if it
// exists on disk), then the project venv (face_verify/venv), then python on PATH.
function resolvePythonBin() {
    const candidates = [];
    if (process.env.FACE_PYTHON_BIN) candidates.push(process.env.FACE_PYTHON_BIN);
    const venv = path.join(FACE_VERIFY_DIR, 'venv');
    candidates.push(process.platform === 'win32'
        ? path.join(venv, 'Scripts', 'python.exe')
        : path.join(venv, 'bin', 'python'));
    for (const c of candidates) {
        try { if (fs.existsSync(c)) return c; } catch (_) { /* try next */ }
    }
    return process.platform === 'win32' ? 'python' : 'python3';
}

let pyProcess = null;
let currentResolve = null;
let currentReject = null;
let currentTimer = null;
let stdoutBuffer = '';
const queue = [];
let processing = false;

function settle(fn, arg) {
    if (currentTimer) { clearTimeout(currentTimer); currentTimer = null; }
    const resolve = currentResolve, reject = currentReject;
    currentResolve = null; currentReject = null;
    if (fn === 'resolve' && resolve) resolve(arg);
    if (fn === 'reject' && reject) reject(arg);
}

function initPyProcess() {
    const pythonBin = resolvePythonBin();
    console.log(`[FaceEngine] spawning worker: ${pythonBin}`);
    pyProcess = spawn(pythonBin, [WORKER_SCRIPT], {
        cwd: FACE_VERIFY_DIR,
        env: {
            ...process.env,
            OPENBLAS_NUM_THREADS: '1',
            OMP_NUM_THREADS: '1',
            MKL_NUM_THREADS: '1',
            PYTHONIOENCODING: 'utf-8',
        },
    });

    pyProcess.stdout.on('data', (data) => {
        stdoutBuffer += data.toString();
        let idx;
        while ((idx = stdoutBuffer.indexOf('\n')) >= 0) {
            const line = stdoutBuffer.slice(0, idx);
            stdoutBuffer = stdoutBuffer.slice(idx + 1);
            if (!line.trim()) continue;
            if (currentResolve) {
                try {
                    settle('resolve', JSON.parse(line.trim()));
                } catch (err) {
                    settle('reject', new Error(`FaceEngine parse error: ${line}`));
                }
            }
        }
    });

    pyProcess.stderr.on('data', (d) => {
        const msg = d.toString().trim();
        if (msg) console.error(`[FaceEngine worker] ${msg}`);
    });

    pyProcess.on('error', (err) => {
        console.error(`[FaceEngine] spawn failed (${pythonBin}): ${err.message}`);
        pyProcess = null;
        settle('reject', err);
        processing = false;
    });

    pyProcess.on('close', (code) => {
        console.warn(`[FaceEngine] worker exited (code ${code}); will respawn on next request.`);
        pyProcess = null;
        stdoutBuffer = '';
        settle('reject', new Error('Face worker exited'));
        processing = false;
    });
}

// Warm up on boot so the first real request is fast.
initPyProcess();

function request(obj) {
    return new Promise((resolve, reject) => {
        queue.push({ payload: JSON.stringify(obj), resolve, reject });
        processQueue();
    });
}

async function processQueue() {
    if (processing || queue.length === 0) return;
    processing = true;
    const { payload, resolve, reject } = queue.shift();
    try {
        if (!pyProcess) {
            initPyProcess();
            await new Promise((r) => setTimeout(r, 300));
        }
        currentResolve = resolve;
        currentReject = reject;
        currentTimer = setTimeout(() => {
            settle('reject', new Error('Face worker timeout'));
            processing = false;
            processQueue();
        }, REQUEST_TIMEOUT_MS);

        pyProcess.stdin.write(payload + '\n');

        // Release the processing lock once the in-flight request settles.
        const checkDone = setInterval(() => {
            if (currentResolve === null) {
                clearInterval(checkDone);
                processing = false;
                processQueue();
            }
        }, 5);
    } catch (err) {
        reject(new Error(`FaceEngine crash: ${err.message}`));
        processing = false;
        processQueue();
    }
}

/** Embed the largest face → { embedding: number[]|null, error: string|null }.
 *  LENIENT (rotation retries, no positioning/liveness guards) — used for ENROLL
 *  from stored/captured photos, the same as the face app's enroll_image path. */
function embed(image) {
    return request({ cmd: 'embed', image });
}

/** STRICT live embed for a LIVE punch/break selfie. Runs the face-attendance app's
 *  kiosk pipeline (single-face + centering + proximity guards, optional frontal +
 *  anti-spoofing) before producing a descriptor, so a spoofed or off-spec frame is
 *  rejected with an actionable message. → { embedding: number[]|null, error: string|null }.
 *  Tunable via env: FACE_LIVE_GUARDS, FACE_LIVENESS, FACE_FRONTAL_CHECK,
 *  FACE_CENTER_TOL_X/Y, FACE_MIN_WIDTH, FACE_MAX_WIDTH (see verify_core.py). */
function embedLive(image) {
    return request({ cmd: 'embed_live', image });
}

/** Verify selfie vs reference (image or URL) → { match, distance, error }. */
function verify({ selfie, reference, referenceUrl }) {
    return request({ cmd: 'verify', selfie, reference, reference_url: referenceUrl });
}

module.exports = { embed, embedLive, verify };
