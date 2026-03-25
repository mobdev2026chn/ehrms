import 'package:flutter/material.dart';
import '../config/app_colors.dart';

class MenuIconButton extends StatelessWidget {
  const MenuIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (innerContext) => IconButton(
        icon: Icon(Icons.menu, color: AppColors.primary),
        tooltip: MaterialLocalizations.of(innerContext).openAppDrawerTooltip,
        onPressed: () {
          final scaffold = Scaffold.maybeOf(innerContext);
          if (scaffold == null || !scaffold.hasDrawer) return;
          if (scaffold.isDrawerOpen) return;
          scaffold.openDrawer();
        },
      ),
    );
  }
}
