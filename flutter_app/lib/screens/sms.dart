import 'package:flutter/material.dart';

import 'sms_section.dart';

/// Page dédiée aux SMS (identifiants SMSBUS, solde, modèles, journal).
class SmsScreen extends StatelessWidget {
  const SmsScreen({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: const [SmsSection()],
  );
}
