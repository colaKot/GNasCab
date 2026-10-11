part of '../user_management_view.dart';

class _UserManagementSidebar extends StatelessWidget {
  final UserManagementController ctrl;
  const _UserManagementSidebar({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _UserManagementSidebarHeader(ctrl: ctrl),
        const SizedBox(height: 2),
        Expanded(child: _UserManagementUserList(ctrl: ctrl)),
      ],
    );
  }
}
