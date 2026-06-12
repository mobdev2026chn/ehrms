const {
    isCurrentlyInLeaveSession,
    isWithinSecondHalfEarlyLoginWindow,
    getLeaveMessageForUI,
    canCheckInWithHalfDayLeave,
    canCheckOutWithHalfDayLeave,
    getHalfDaySessionMessage,
} = require('./src/utils/leaveAttendanceHelper');

const shiftStart = '10:00';
const shiftEnd = '19:00';
const halfDaySettings = null; // "All Genrel Shift" has halfDaySettings.enabled = false
const tz = 'Asia/Kolkata';

const leave = {
    leaveType: 'Half Day',
    status: 'Approved',
    session: '1',
    halfDaySession: 'First Half Day',
    halfDayType: 'First Half Day',
};

for (const clientLocalTime of ['09:30', '10:00', '11:00', '13:00', '13:59', '14:00', '14:15', '14:30', '15:00', '17:00', '19:00', '19:30']) {
    const [h, m] = clientLocalTime.split(':').map(Number);
    const currentMinutesOverride = h * 60 + m;
    const now = new Date();

    const inLeaveSession = isCurrentlyInLeaveSession(leave, now, shiftStart, shiftEnd, tz, halfDaySettings, currentMinutesOverride);
    const earlyWindow = isWithinSecondHalfEarlyLoginWindow(leave, now, shiftStart, shiftEnd, tz, halfDaySettings, currentMinutesOverride);
    const checkIn = canCheckInWithHalfDayLeave(leave, now, shiftStart, shiftEnd, tz, halfDaySettings, 0);
    const checkOut = canCheckOutWithHalfDayLeave(leave, now, shiftStart, shiftEnd, tz, halfDaySettings);

    const inLeaveSessionBlocking = inLeaveSession && !earlyWindow;
    let checkInAllowed = checkIn.allowed;
    let checkOutAllowed = checkOut.allowed;
    const sessionNum = '1';
    if (inLeaveSessionBlocking) {
        if (sessionNum === '1') {
            checkInAllowed = checkIn.allowed;
            checkOutAllowed = false;
        } else {
            checkInAllowed = false;
            checkOutAllowed = false;
        }
    } else if (earlyWindow) {
        checkOutAllowed = false;
    }

    console.log(clientLocalTime, JSON.stringify({ inLeaveSession, earlyWindow, inLeaveSessionBlocking, checkInAllowed, checkOutAllowed, checkInMsg: checkIn.message, checkOutMsg: checkOut.message }));
}
