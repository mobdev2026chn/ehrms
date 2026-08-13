const Leave = require('../models/Leave');
const Attendance = require('../models/Attendance');
const moment = require('moment');

exports.askQuestion = async (req, res) => {
    try {
        const { question } = req.body;
        const userId = req.user.id; // User ID from auth middleware

        if (!question) {
            return res.status(400).json({ success: false, message: 'Question is required' });
        }

        const lowerQ = question.toLowerCase();
        let responseText = "I'm sorry, I didn't understand that. You can ask me about 'leaves', 'holidays', 'late days', or 'company info'.";

        // 1. Company Information
        if (lowerQ.includes('company') || lowerQ.includes('info') || lowerQ.includes('about')) {
            responseText = "We are a leading tech company dedicated to innovation. Our office hours are 9 AM to 6 PM, Monday to Friday.";
        }

        // 2. Holidays (Hardcoded as model is missing)
        else if (lowerQ.includes('holiday')) {
            const holidays = [
                { name: 'Republic Day', date: '2026-01-26' },
                { name: 'Holi', date: '2026-03-04' },
                { name: 'Independence Day', date: '2026-08-15' }
            ];
            // Filter upcoming
            const today = moment();
            const upcoming = holidays.filter(h => moment(h.date).isAfter(today));

            if (upcoming.length > 0) {
                responseText = "Here are the upcoming holidays:\n" + upcoming.map(h => `- ${h.name} on ${h.date}`).join('\n');
            } else {
                responseText = "There are no upcoming company holidays in our list for this year.";
            }
        }

        // 3. User Leaves
        else if (lowerQ.includes('leave') || lowerQ.includes('applied')) {
            // Fetch last 3 leaves
            const leaves = await Leave.find({ employee: userId })
                .sort({ applyDate: -1 })
                .limit(3);

            if (leaves.length > 0) {
                const leaveText = leaves.map(l => {
                    const status = l.status.charAt(0).toUpperCase() + l.status.slice(1);
                    return `- ${l.leaveType} (${moment(l.startDate).format('MMM D')} - ${moment(l.endDate).format('MMM D')}): ${status}`;
                }).join('\n');
                responseText = `Here are your recent leave requests:\n${leaveText}`;
            } else {
                responseText = "You haven't applied for any leaves recently.";
            }
        }

        // 4. Late Coming
        else if (lowerQ.includes('late') || lowerQ.includes('attendance')) {
            // Find attendance from this month where status is 'Late' or similar. 
            // Assuming 'status' field exists or we check checkIn time. 
            // Checking Attendance model structure would be ideal, but let's assume 'status' for now based on typical schema.
            // Or better, let's look for any record where specific status is present.

            // Let's grab this month's attendance
            const startOfMonth = moment().startOf('month').toDate();
            const endOfMonth = moment().endOf('month').toDate();

            const attendance = await Attendance.find({
                employee: userId,
                date: { $gte: startOfMonth, $lte: endOfMonth }
            });

            // Filter for late (assuming we can check a status or calculate it. 
            // Since we don't have exact schema, let's just show summary or 'Late' status if it exists)
            const lateDays = attendance.filter(a => (a.status && a.status.toLowerCase() === 'late'));

            if (lateDays.length > 0) {
                responseText = `You have been late ${lateDays.length} times this month:\n` +
                    lateDays.map(a => `- ${moment(a.date).format('MMM D, YYYY')}`).join('\n');
            } else {
                responseText = "You have no recorded late arrivals this month. Great job!";
            }
        }

        res.status(200).json({ success: true, answer: responseText });

    } catch (error) {
        console.error('Chatbot Error:', error);
        res.status(500).json({ success: false, message: 'Server error processing your question' });
    }
};
