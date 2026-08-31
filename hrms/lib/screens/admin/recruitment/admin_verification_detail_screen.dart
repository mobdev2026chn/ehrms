// lib/screens/admin/recruitment/admin_verification_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../config/app_colors.dart';
import '../../../services/api_client.dart';
import '../../../utils/snackbar_utils.dart';
import 'admin_verifications_screen.dart';

class AdminVerificationDetailScreen extends StatefulWidget {
  final AdminCandidateVerification candidate;

  const AdminVerificationDetailScreen({super.key, required this.candidate});

  @override
  State<AdminVerificationDetailScreen> createState() => _AdminVerificationDetailScreenState();
}

class _AdminVerificationDetailScreenState extends State<AdminVerificationDetailScreen> {
  final ApiClient _api = ApiClient();
  late AdminCandidateVerification _c;

  @override
  void initState() {
    super.initState();
    _c = widget.candidate;
  }

  int get _verifiedDocs => _c.documents.where((d) => d.status == 'Verified').length;
  int get _pendingReviewDocs => _c.documents.where((d) => d.status == 'Pending Review').length;
  int get _outstandingDocs => _c.documents.where((d) => d.status == 'Missing' || d.status == 'Not Submitted').length;

  void _showDocumentPreview(VerificationDoc doc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFFEFAA1F), size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${doc.title} Preview', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                  Text(doc.fileName, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                ],
              ),
            ),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insert_drive_file_outlined, size: 54, color: Color(0xFFEFAA1F)),
              const SizedBox(height: 12),
              Text(doc.fileName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
              const SizedBox(height: 4),
              const Text('Format: PDF Document • Size: 1.4 MB', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                child: Text(
                  '[Simulated PDF Document View - High-resolution scanned copy of the candidate\'s official ${doc.title} submitted during onboarding.]',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF475569), height: 1.4),
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEFAA1F),
              foregroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Close Preview', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  void _verifyDoc(VerificationDoc doc) {
    setState(() => doc.status = 'Verified');
    try {
      _api.request('/admin/recruitment/verifications/${_c.id}/verify', method: 'POST', data: {'document': doc.title});
    } catch (_) {}
    SnackBarUtils.showSnackBar(context, '${doc.title} marked as Verified');
  }

  void _rejectDoc(VerificationDoc doc) {
    setState(() => doc.status = 'Missing');
    try {
      _api.request('/admin/recruitment/verifications/${_c.id}/reject', method: 'POST', data: {'document': doc.title});
    } catch (_) {}
    SnackBarUtils.showSnackBar(context, '${doc.title} rejected / marked as missing');
  }

  void _simulateUpload(VerificationDoc doc) {
    setState(() {
      doc.status = 'Pending Review';
    });
    SnackBarUtils.showSnackBar(context, 'Document uploaded for ${doc.title}. Now ready for review.');
  }

  void _convertToStaff() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.how_to_reg_rounded, color: Color(0xFF16A34A), size: 22),
            SizedBox(width: 8),
            Text('Convert to Staff', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Text('All documents verified! Are you ready to convert ${_c.fullName} into an active employee staff record?', style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B)))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _api.request('/admin/recruitment/verifications/${_c.id}/convert-to-staff', method: 'POST');
              } catch (_) {}
              if (mounted) {
                SnackBarUtils.showSnackBar(context, '${_c.fullName} converted to Staff successfully!');
                Navigator.pop(context, true);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('Confirm Onboard', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = _c.documents.isNotEmpty ? _verifiedDocs / _c.documents.length : 0.0;
    final submittedDocs = _c.documents.where((d) => d.status == 'Verified' || d.status == 'Pending Review').toList();
    final missingDocs = _c.documents.where((d) => d.status == 'Missing' || d.status == 'Not Submitted').toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Verification Checklist Details',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── CANDIDATE PROFILE & STATUS SUMMARY CARD ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF1F5F9)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFFF1F5F9),
                      child: Text(_c.initials, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_c.fullName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                          Text(_c.position, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
                      child: Text('ID: ${_c.id}', style: const TextStyle(fontSize: 9.5, fontFamily: 'monospace', fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Overall Progress
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Overall Progress', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                    Text('$_verifiedDocs of ${_c.documents.length} Verified', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation<Color>(_c.isCompleted ? const Color(0xFF16A34A) : const Color(0xFFEFAA1F)),
                    minHeight: 6,
                  ),
                ),
                const Divider(height: 20, color: Color(0xFFE2E8F0)),

                _infoRow('EMAIL', _c.email),
                _infoRow('PHONE', _c.phone),
                const Divider(height: 20, color: Color(0xFFE2E8F0)),

                // Status Summary Metrics
                const Text('STATUS SUMMARY', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
                const SizedBox(height: 8),
                _metricRow('Verified Documents', '$_verifiedDocs', const Color(0xFF16A34A), const Color(0xFFDCFCE7)),
                _metricRow('Pending Review', '$_pendingReviewDocs', const Color(0xFFD97706), const Color(0xFFFEF3C7)),
                _metricRow('Outstanding Documents', '$_outstandingDocs', const Color(0xFFDC2626), const Color(0xFFFEE2E2)),
                const SizedBox(height: 14),

                // Final Verification Buttons
                const Text('FINAL VERIFICATION', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _c.isCompleted ? _convertToStaff : null,
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                    label: const Text('Convert to Staff', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFCBD5E1),
                      disabledForegroundColor: const Color(0xFF94A3B8),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => SnackBarUtils.showSnackBar(context, 'Process held for ${_c.fullName}'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFD97706),
                          side: const BorderSide(color: Color(0xFFFDE68A)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        child: const Text('Hold Process', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => SnackBarUtils.showSnackBar(context, '${_c.fullName} candidate verification rejected'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFDC2626),
                          side: const BorderSide(color: Color(0xFFFECACA)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        child: const Text('Reject Candidate', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── SUBMITTED DOCUMENTS SECTION ──
          if (submittedDocs.isNotEmpty) ...[
            Row(
              children: const [
                Icon(Icons.check_circle_outline_rounded, size: 16, color: Color(0xFF16A34A)),
                SizedBox(width: 6),
                Text('Submitted Documents', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
              ],
            ),
            const SizedBox(height: 10),
            ...submittedDocs.map((doc) => _buildSubmittedDocCard(doc)),
          ],

          // ── NEED TO BE SUBMITTED SECTION ──
          if (missingDocs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: const [
                Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFDC2626)),
                SizedBox(width: 6),
                Text('Need to be Submitted', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
              ],
            ),
            const SizedBox(height: 10),
            ...missingDocs.map((doc) => _buildMissingDocCard(doc)),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 70, child: Text(label, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8)))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)))),
        ],
      ),
    );
  }

  Widget _metricRow(String label, String count, Color color, Color bg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
            child: Text(count, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: color)),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmittedDocCard(VerificationDoc doc) {
    final isVerified = doc.status == 'Verified';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(doc.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: isVerified ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isVerified ? 'VERIFIED' : 'PENDING REVIEW',
                  style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: isVerified ? const Color(0xFF16A34A) : const Color(0xFFD97706)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(doc.fileName, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          const SizedBox(height: 2),
          Text('Uploaded: ${DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 2)))}', style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
          const SizedBox(height: 10),

          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _showDocumentPreview(doc),
                icon: const Icon(Icons.remove_red_eye_outlined, size: 14),
                label: const Text('Preview', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF475569),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
              const Spacer(),
              if (!isVerified) ...[
                ElevatedButton.icon(
                  onPressed: () => _verifyDoc(doc),
                  icon: const Icon(Icons.check_rounded, size: 14),
                  label: const Text('Verify', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    elevation: 0,
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  onPressed: () => _rejectDoc(doc),
                  icon: const Icon(Icons.close_rounded, size: 14),
                  label: const Text('Reject', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFFECACA)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMissingDocCard(VerificationDoc doc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(doc.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
          const SizedBox(height: 4),
          const Text('Document has not been uploaded by candidate yet.', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          const SizedBox(height: 10),

          ElevatedButton.icon(
            onPressed: () => _simulateUpload(doc),
            icon: const Icon(Icons.upload_file_rounded, size: 14),
            label: const Text('Simulate Upload', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEFAA1F),
              foregroundColor: const Color(0xFF0F172A),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }
}
