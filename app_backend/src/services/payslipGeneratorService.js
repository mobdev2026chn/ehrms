const { jsPDF } = require('jspdf');
const Payroll = require('../models/Payroll');
const Staff = require('../models/Staff');
const Company = require('../models/Company');
const Attendance = require('../models/Attendance');

// Import calculateAttendanceStats from payrollController
const { calculateAttendanceStats } = require('../controllers/payrollController');

class PayslipGeneratorService {
  /**
   * Get payslip data for a payroll record
   */
  async getPayslipData(payrollId) {
    // Fetch payroll with populated employee
    const payroll = await Payroll.findById(payrollId)
      .populate('employeeId', 'name employeeId designation department email phone bankDetails pan uan esiNumber')
      .lean();

    if (!payroll) {
      throw new Error('Payroll not found');
    }

    const staff = payroll.employeeId;
    if (!staff) {
      throw new Error('Employee not found');
    }

    // Fetch business details if businessId exists
    let business = null;
    if (payroll.businessId) {
      business = await Company.findById(payroll.businessId).lean();
    }

    // Calculate attendance stats using the same function from payrollController
    // This ensures consistency with the payroll generation
    const employeeId = payroll.employeeId._id || payroll.employeeId;
    let attendanceStats;
    try {
        attendanceStats = await calculateAttendanceStats(
            employeeId,
            payroll.month,
            payroll.year
        );
        console.log(`[PayslipGenerator] Attendance Stats from calculateAttendanceStats:`, attendanceStats);
    } catch (error) {
        console.error(`[PayslipGenerator] Error calculating attendance stats:`, error);
        // Fallback to default values if calculation fails
        attendanceStats = {
            workingDays: 0,
            presentDays: 0,
            absentDays: 0,
            holidays: 0
        };
    }

    const workingDays = attendanceStats.workingDays || 0;
    const workingDaysFullMonth = attendanceStats.workingDaysFullMonth ?? workingDays;
    const presentDays = attendanceStats.presentDays || 0;
    const absentDays = attendanceStats.absentDays || 0;
    const lopDays = absentDays; // Loss of Pay days = Absent days
    const halfDayPaidLeaveCount = attendanceStats.halfDayPaidLeaveCount ?? 0;
    const leaveDays = attendanceStats.leaveDays ?? 0;

    console.log(`[PayslipGenerator] Using Attendance - Working Days: ${workingDays}, Present: ${presentDays}, Absent: ${absentDays}, Half-day paid leave: ${halfDayPaidLeaveCount}, Leave days: ${leaveDays}`);

    return { 
      payroll, 
      staff, 
      business,
      attendance: {
        workingDays,
        workingDaysFullMonth,
        presentDays,
        absentDays,
        lopDays,
        halfDayPaidLeaveCount,
        leaveDays
      }
    };
  }

  /**
   * Generate payslip PDF buffer (for direct download/view)
   */
  async generatePayslipPDF(payrollId) {
    try {
      console.log(`[PayslipGenerator] Generating payslip PDF for payroll ID: ${payrollId}`);
      const data = await this.getPayslipData(payrollId);
      console.log(`[PayslipGenerator] Payslip Data Retrieved:`);
      console.log(`[PayslipGenerator] - Payroll ID: ${data.payroll._id}`);
      console.log(`[PayslipGenerator] - Gross Salary: ${data.payroll.grossSalary}`);
      console.log(`[PayslipGenerator] - Deductions: ${data.payroll.deductions}`);
      console.log(`[PayslipGenerator] - Net Pay: ${data.payroll.netPay}`);
      console.log(`[PayslipGenerator] - Components Count: ${data.payroll.components?.length || 0}`);
      console.log(`[PayslipGenerator] - Working Days: ${data.attendance.workingDays}`);
      console.log(`[PayslipGenerator] - Present Days: ${data.attendance.presentDays}`);
      console.log(`[PayslipGenerator] - Absent Days: ${data.attendance.absentDays}`);
      return this.createPayslipPDF(data);
    } catch (error) {
      console.error('[PayslipGenerator] Error generating payslip PDF:', error);
      throw new Error(`Failed to generate payslip PDF: ${error.message}`);
    }
  }

  /**
   * Create payslip PDF document
   */
  createPayslipPDF(data) {
    const { payroll, staff, business, attendance } = data;
    
    console.log(`[PayslipGenerator] Creating PDF with data:`, {
      payrollId: payroll._id,
      grossSalary: payroll.grossSalary,
      deductions: payroll.deductions,
      netPay: payroll.netPay,
      componentsCount: payroll.components?.length || 0,
      earningsCount: payroll.components?.filter(c => c.type === 'earning').length || 0,
      deductionsCount: payroll.components?.filter(c => c.type === 'deduction').length || 0,
      workingDays: attendance.workingDays,
      presentDays: attendance.presentDays
    });
    const doc = new jsPDF();
    const pageWidth = doc.internal.pageSize.getWidth();
    const pageHeight = doc.internal.pageSize.getHeight();
    const margin = 15;
    let yPosition = margin;

    // Helper function to add a new page if needed
    const checkPageBreak = (requiredSpace) => {
      if (yPosition + requiredSpace > pageHeight - margin) {
        doc.addPage();
        yPosition = margin;
      }
    };

    // ============================================
    // HEADER SECTION
    // ============================================
    doc.setFontSize(18);
    doc.setFont('helvetica', 'bold');
    const companyName = business?.name || 'Company Name';
    doc.text(companyName, pageWidth / 2, yPosition, { align: 'center' });
    yPosition += 8;

    doc.setFontSize(12);
    doc.setFont('helvetica', 'normal');
    if (business?.address) {
      const address = `${business.address.street || ''}, ${business.address.city || ''}, ${business.address.state || ''} - ${business.address.zip || ''}`;
      const addressLines = doc.splitTextToSize(address, pageWidth - 2 * margin);
      doc.text(addressLines, pageWidth / 2, yPosition, { align: 'center' });
      yPosition += addressLines.length * 5 + 5;
    }

    // Title
    doc.setFontSize(16);
    doc.setFont('helvetica', 'bold');
    doc.text('SALARY STATEMENT', pageWidth / 2, yPosition, { align: 'center' });
    yPosition += 10;

    // Month and Year
    const monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    const monthName = monthNames[payroll.month - 1];
    doc.setFontSize(12);
    doc.setFont('helvetica', 'normal');
    doc.text(`For the month of ${monthName} ${payroll.year}`, pageWidth / 2, yPosition, { align: 'center' });
    yPosition += 15;

    // ============================================
    // EMPLOYEE INFORMATION & ATTENDANCE SUMMARY (Two Column Layout)
    // ============================================
    checkPageBreak(50);
    const columnWidth = (pageWidth - 2 * margin) / 2;
    const leftColumnX = margin;
    const rightColumnX = margin + columnWidth + 10;
    const startY = yPosition;

    // Left Column: Employee Information
    doc.setFontSize(11);
    doc.setFont('helvetica', 'bold');
    doc.text('Employee Information', leftColumnX, yPosition);
    yPosition += 8;

    doc.setFont('helvetica', 'normal');
    doc.setFontSize(10);
    
    const employeeInfo = [
      { label: 'Employee Name:', value: staff.name || 'N/A' },
      { label: 'Employee ID:', value: staff.employeeId || 'N/A' },
      { label: 'Designation:', value: staff.designation || 'N/A' },
      { label: 'Department:', value: staff.department || 'N/A' },
    ];

    if (staff.email) {
      employeeInfo.push({ label: 'Email:', value: staff.email });
    }
    if (staff.phone) {
      employeeInfo.push({ label: 'Phone:', value: staff.phone });
    }

    employeeInfo.forEach((info) => {
      doc.setFont('helvetica', 'bold');
      doc.text(info.label, leftColumnX, yPosition);
      doc.setFont('helvetica', 'normal');
      doc.text(info.value, leftColumnX + 60, yPosition);
      yPosition += 6;
    });

    // Right Column: Attendance Summary (aligned with Employee Information)
    yPosition = startY;
    doc.setFontSize(11);
    doc.setFont('helvetica', 'bold');
    doc.text('Attendance Summary', rightColumnX, yPosition);
    yPosition += 8;

    doc.setFont('helvetica', 'normal');
    doc.setFontSize(10);
    
    const attendanceInfo = [
      { label: 'Working Days:', value: attendance.workingDays || 0 },
      { label: 'This Month Working Days:', value: attendance.workingDaysFullMonth ?? attendance.workingDays ?? 0 },
      { label: 'Present Days:', value: attendance.presentDays || 0 },
      { label: 'Absent Days:', value: attendance.absentDays || 0 },
      { label: 'Half Day Paid Leave:', value: attendance.halfDayPaidLeaveCount ?? 0 },
      { label: 'Leave Days:', value: attendance.leaveDays ?? 0 },
      { label: 'Loss of Pay (LOP) Days:', value: attendance.lopDays || 0 },
    ];

    attendanceInfo.forEach((info) => {
      doc.setFont('helvetica', 'bold');
      doc.text(info.label, rightColumnX, yPosition);
      doc.setFont('helvetica', 'normal');
      doc.text(info.value.toString(), rightColumnX + 60, yPosition);
      yPosition += 6;
    });

    // Move to the maximum Y position from both columns
    const maxY = Math.max(
      startY + 8 + (employeeInfo.length * 6),
      startY + 8 + (attendanceInfo.length * 6)
    );
    yPosition = maxY + 10;

    // ============================================
    // EARNINGS SECTION
    // ============================================
    checkPageBreak(50);
    doc.setFontSize(11);
    doc.setFont('helvetica', 'bold');
    doc.text('EARNINGS', margin, yPosition);
    yPosition += 8;

    const earnings = payroll.components?.filter(c => c.type === 'earning') || [];
    let totalEarnings = 0;

    if (earnings.length === 0) {
      doc.setFont('helvetica', 'normal');
      doc.setFontSize(10);
      doc.text('No earnings recorded', margin + 5, yPosition);
      yPosition += 6;
    } else {
      doc.setFontSize(10);
      earnings.forEach((earning) => {
        doc.setFont('helvetica', 'normal');
        doc.text(earning.name, margin + 5, yPosition);
        const amount = earning.amount || 0;
        totalEarnings += amount;
        // Use "Rs." instead of rupee symbol to avoid rendering issues
        const amountStr = `Rs. ${amount.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
        doc.text(amountStr, pageWidth - margin - 40, yPosition, { align: 'right' });
        yPosition += 6;
      });
    }

    // Total Earnings
    yPosition += 3;
    doc.setDrawColor(0, 0, 0);
    doc.line(margin, yPosition, pageWidth - margin, yPosition);
    yPosition += 6;
    doc.setFont('helvetica', 'bold');
    doc.text('Total Earnings', margin + 5, yPosition);
    const totalEarningsStr = `Rs. ${totalEarnings.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
    doc.text(totalEarningsStr, pageWidth - margin - 40, yPosition, { align: 'right' });
    yPosition += 10;

    // ============================================
    // DEDUCTIONS SECTION
    // ============================================
    checkPageBreak(50);
    doc.setFontSize(11);
    doc.setFont('helvetica', 'bold');
    doc.text('DEDUCTIONS', margin, yPosition);
    yPosition += 8;

    const deductions = payroll.components?.filter(c => c.type === 'deduction') || [];
    let totalDeductions = 0;

    if (deductions.length === 0) {
      doc.setFont('helvetica', 'normal');
      doc.setFontSize(10);
      doc.text('No deductions', margin + 5, yPosition);
      yPosition += 6;
    } else {
      doc.setFontSize(10);
      deductions.forEach((deduction) => {
        doc.setFont('helvetica', 'normal');
        doc.text(deduction.name, margin + 5, yPosition);
        const amount = deduction.amount || 0;
        totalDeductions += amount;
        // Use "Rs." instead of rupee symbol to avoid rendering issues
        const amountStr = `Rs. ${amount.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
        doc.text(amountStr, pageWidth - margin - 40, yPosition, { align: 'right' });
        yPosition += 6;
      });
    }

    // Total Deductions
    yPosition += 3;
    doc.setDrawColor(0, 0, 0);
    doc.line(margin, yPosition, pageWidth - margin, yPosition);
    yPosition += 6;
    doc.setFont('helvetica', 'bold');
    doc.text('Total Deductions', margin + 5, yPosition);
    const totalDeductionsStr = `Rs. ${totalDeductions.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
    doc.text(totalDeductionsStr, pageWidth - margin - 40, yPosition, { align: 'right' });
    yPosition += 10;

    // ============================================
    // NET PAY SECTION
    // ============================================
    checkPageBreak(20);
    doc.setDrawColor(0, 0, 0);
    doc.setLineWidth(0.5);
    doc.line(margin, yPosition, pageWidth - margin, yPosition);
    yPosition += 8;
    
    doc.setFontSize(12);
    doc.setFont('helvetica', 'bold');
    doc.text('NET PAY', margin + 5, yPosition);
    const netPayStr = `Rs. ${(payroll.netPay || 0).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
    doc.text(netPayStr, pageWidth - margin - 40, yPosition, { align: 'right' });
    yPosition += 10;

    // ============================================
    // FOOTER SECTION
    // ============================================
    checkPageBreak(30);
    yPosition = pageHeight - 40;
    
    doc.setFontSize(8);
    doc.setFont('helvetica', 'normal');
    doc.setTextColor(128, 128, 128);
    
    const footerText = 'This is a system generated document. No signature required.';
    doc.text(footerText, pageWidth / 2, yPosition, { align: 'center' });
    yPosition += 5;
    
    const generatedDate = new Date().toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric'
    });
    doc.text(`Generated on: ${generatedDate}`, pageWidth / 2, yPosition, { align: 'center' });

    // Convert to buffer
    const pdfOutput = doc.output('arraybuffer');
    return Buffer.from(pdfOutput);
  }
}

module.exports = new PayslipGeneratorService();
