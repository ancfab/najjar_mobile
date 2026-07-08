import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/availability_search_card.dart';
import '../widgets/balance_card.dart';
import '../widgets/custom_bottom_nav.dart';
import '../widgets/home_header.dart';
import '../widgets/last_payment_card.dart';
import '../widgets/metric_card.dart';
import '../widgets/scan_fabric_button.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedNavIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const HomeHeader(userName: 'Alex Sterling'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const BalanceCard(amount: '\$42,850.00'),
                    const SizedBox(height: 12),
                    MetricCard(
                      icon: Icons.receipt_long_rounded,
                      iconBoxColor: AppColors.darkTeal,
                      backgroundColor: AppColors.mint,
                      valueText: '12',
                      subtitle: 'Active Orders',
                      contentColor: AppColors.darkTeal,
                    ),
                    const SizedBox(height: 12),
                    MetricCard(
                      icon: Icons.request_quote_rounded,
                      iconBoxColor: AppColors.darkRedBrown,
                      backgroundColor: AppColors.peach,
                      borderColor: AppColors.border,
                      valueText: '\$12,450.00',
                      subtitle: 'Overdue Invoices',
                      contentColor: AppColors.darkRedBrown,
                    ),
                    const SizedBox(height: 12),
                    const LastPaymentCard(amount: '\$1,250.00', date: 'Oct 24'),
                    const SizedBox(height: 16),
                    ScanFabricButton(
                      label: 'Scan Fabric Availability',
                      onTap: () {
                        // TODO: Wire up the fabric availability scanning flow.
                      },
                    ),
                    const SizedBox(height: 16),
                    AvailabilitySearchCard(
                      title: 'Check Availability',
                      hintText: 'Enter Catalogue Code',
                      helperText:
                          'Quickly check availability across all warehouses.',
                      onSearch: () {
                        // TODO: Wire up catalogue availability search.
                      },
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: CustomBottomNav(
                currentIndex: _selectedNavIndex,
                onTap: (index) {
                  setState(() => _selectedNavIndex = index);
                  // TODO: Navigate to the corresponding screen once implemented.
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
