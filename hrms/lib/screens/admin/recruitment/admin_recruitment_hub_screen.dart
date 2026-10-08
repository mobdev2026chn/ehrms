// lib/screens/admin/recruitment/admin_recruitment_hub_screen.dart
// Recruitment hub: one place to reach every recruitment screen.

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../widgets/app_drawer.dart';
import 'admin_appointments_screen.dart';
import 'admin_candidate_disposition_screen.dart';
import 'admin_candidates_screen.dart';
import 'admin_communications_screen.dart';
import 'admin_interview_flow_screen.dart';
import 'admin_interview_rounds_screen.dart';
import 'admin_job_openings_screen.dart';
import 'admin_offer_letter_screen.dart';
import 'admin_offer_templates_screen.dart';
import 'admin_recruitment_analytics_screen.dart';
import 'admin_selected_rejected_screen.dart';
import 'admin_verifications_screen.dart';
import 'rec_widgets.dart';

class AdminRecruitmentHubScreen extends StatelessWidget {
  const AdminRecruitmentHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scaffoldKey = GlobalKey<ScaffoldState>();
    final sections = <(String, List<(String, IconData, Widget Function())>)>[
      ('Overview', [
        ('Analytics', Icons.insights_rounded, () => const AdminRecruitmentAnalyticsScreen()),
      ]),
      ('Sourcing', [
        ('Job Openings', Icons.work_outline_rounded, () => const AdminJobOpeningsScreen()),
        ('Candidates', Icons.people_outline_rounded, () => const AdminCandidatesScreen()),
        ('Disposition', Icons.assignment_late_outlined, () => const AdminCandidateDispositionScreen()),
      ]),
      ('Interviews', [
        ('Appointments', Icons.calendar_today_outlined, () => const AdminAppointmentsScreen()),
        ('Interview Flow', Icons.account_tree_outlined, () => const AdminInterviewFlowScreen()),
        ('Rounds', Icons.fact_check_outlined, () => const AdminInterviewRoundsScreen()),
        ('Selected / Rejected', Icons.how_to_reg_outlined, () => const AdminSelectedRejectedScreen()),
      ]),
      ('Offers & Onboarding', [
        ('Offer Letters', Icons.mail_outline_rounded, () => const AdminOfferLetterScreen()),
        ('Letter Templates', Icons.description_outlined, () => const AdminOfferTemplatesScreen()),
        ('Documents', Icons.folder_shared_outlined, () => const AdminVerificationsScreen(initialTab: 0)),
        ('Convert to Staff', Icons.badge_outlined, () => const AdminVerificationsScreen(initialTab: 2)),
        ('Joining', Icons.door_front_door_outlined, () => const AdminVerificationsScreen(initialTab: 3)),
      ]),
      ('Settings', [
        ('Communications', Icons.forum_outlined, () => const AdminCommunicationsScreen()),
      ]),
    ];

    return Scaffold(
      key: scaffoldKey,
      backgroundColor: kRecBg,
      drawer: const AppDrawer(),
      appBar: recAppBar(context, 'Recruitment', drawerKey: scaffoldKey),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: sections
            .expand((s) => [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 10, left: 2),
                    child: Text(s.$1.toUpperCase(),
                        style: AppTextStyles.sectionLabel.copyWith(color: AppColors.textSecondary)),
                  ),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.0,
                    children: s.$2
                        .map((t) => RecCard(
                              margin: EdgeInsets.zero,
                              padding: const EdgeInsets.all(12),
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => t.$3())),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  RecIconTile(t.$2, size: 44),
                                  const SizedBox(height: 10),
                                  Text(t.$1,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: kRecInk, height: 1.25)),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                ])
            .toList(),
      ),
    );
  }
}
