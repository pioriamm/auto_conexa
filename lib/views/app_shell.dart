import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_colors.dart';
import '../viewmodels/navigation_view_model.dart';
import 'widgets/sidebar_button.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.processingPage,
    required this.commissionsPage,
  });

  final Widget processingPage;
  final Widget commissionsPage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Row(
          children: [
            Container(
              width: 260,
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  right: BorderSide(color: AppColors.border),
                ),
              ),
              child: Consumer<NavigationViewModel>(
                builder: (context, vm, _) {
                  return Column(
                    children: [
                      const SizedBox(height: 20),
                      const ListTile(
                        title: Text(
                          'Conexa',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        subtitle: Text('Navegação'),
                      ),
                      const SizedBox(height: 12),
                      SidebarButton(
                        icon: Icons.account_tree_outlined,
                        label: 'Fluxo de cobrança',
                        selected: vm.current == AppSection.fluxoCobranca,
                        onTap: () => vm.setSection(AppSection.fluxoCobranca),
                      ),
                      SidebarButton(
                        icon: Icons.request_quote_outlined,
                        label: 'Comissões',
                        selected: vm.current == AppSection.comissoes,
                        onTap: () => vm.setSection(AppSection.comissoes),
                      ),
                    ],
                  );
                },
              ),
            ),
            Expanded(
              child: Consumer<NavigationViewModel>(
                builder: (context, vm, _) {
                  return IndexedStack(
                    index: vm.current == AppSection.fluxoCobranca ? 0 : 1,
                    children: [processingPage, commissionsPage],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
