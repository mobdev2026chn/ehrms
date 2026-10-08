// The integrations offered on the admin Integrations screen, grouped by category - mirrors the
// web's features/admin/integrations/data/integrations.ts. Only Google Calendar & Meet has a
// backend (/admin/integrations/google-calendar/*); the email services are "Coming soon".

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';

enum IntegrationCategoryKey { email, google }

class IntegrationCategory {
  final IntegrationCategoryKey key;
  final String label;
  final String description;
  final IconData icon;
  const IntegrationCategory(this.key, this.label, this.description, this.icon);
}

class IntegrationDefinition {
  final String id;
  final IntegrationCategoryKey category;
  final String name;
  final String subtitle;
  final String description;
  final IconData icon;
  final Color tone;
  final Color toneBg;

  /// False when the backend has no API for it yet - shown as "Coming soon".
  final bool available;

  const IntegrationDefinition({
    required this.id,
    required this.category,
    required this.name,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.tone,
    required this.toneBg,
    this.available = false,
  });
}

const integrationCategories = <IntegrationCategory>[
  IntegrationCategory(IntegrationCategoryKey.email, 'Email', 'SendGrid, SendPulse, Email config', Icons.mail_outline_rounded),
  IntegrationCategory(IntegrationCategoryKey.google, 'Google', 'Google Calendar & Meet', Icons.calendar_month_outlined),
];

const integrationDefinitions = <IntegrationDefinition>[
  IntegrationDefinition(
    id: 'smtp',
    category: IntegrationCategoryKey.email,
    name: 'Email Configuration',
    subtitle: 'Email Service Providers',
    description: 'Send HRMS emails through your own mail server over SMTP.',
    icon: Icons.mail_outline_rounded,
    tone: AppColors.brandDark,
    toneBg: AppColors.brandLight,
  ),
  IntegrationDefinition(
    id: 'sendgrid',
    category: IntegrationCategoryKey.email,
    name: 'SendGrid',
    subtitle: 'Email Service Integration',
    description: 'Deliver transactional email through a SendGrid account.',
    icon: Icons.send_outlined,
    tone: Color(0xFF0284C7),
    toneBg: Color(0xFFF0F9FF),
  ),
  IntegrationDefinition(
    id: 'sendpulse',
    category: IntegrationCategoryKey.email,
    name: 'SendPulse',
    subtitle: 'Email Service Integration',
    description: 'Deliver transactional email through a SendPulse account.',
    icon: Icons.monitor_heart_outlined,
    tone: Color(0xFF0891B2),
    toneBg: Color(0xFFECFEFF),
  ),
  IntegrationDefinition(
    id: 'google-calendar',
    category: IntegrationCategoryKey.google,
    name: 'Google Calendar & Meet',
    subtitle: 'Calendar & Meet Integration',
    description: 'Sync interviews and meetings with Google Calendar, with a Google Meet link for each.',
    icon: Icons.calendar_month_outlined,
    tone: AppColors.info,
    toneBg: Color(0xFFEFF6FF),
    available: true,
  ),
];
