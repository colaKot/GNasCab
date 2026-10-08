part of '../user_management_view.dart';

class _UserManagementPermissionsTab extends StatelessWidget {
  final int uid;
  final UserManagementController ctrl;
  const _UserManagementPermissionsTab({required this.uid, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<UserManagementController>(
      id: 'permissions_$uid',
      builder: (ctrl) {
        if (!ctrl.userAccessPolicies.containsKey(uid)) {
          ctrl.getAccessPolicy(uid);
        }

        final policy = ctrl.userAccessPolicies[uid];
        if (policy == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final allowedRaw = policy['allowed_apps'];
        final List<String>? allowedApps = allowedRaw is List
            ? allowedRaw.map((e) => e.toString()).toList()
            : null;
        final permsRaw = policy['permissions'];
        final initial = permsRaw is List
            ? permsRaw.cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];

        return CustomAccessPolicyEditor(
          initialAllowedApps: allowedApps,
          initialPermissions: initial,
          availableApps:
              CurrentUserController.instance.apps?.allApp ?? const <String>[],
          onSave: (apps, permissions) async {
            return await ctrl.setAccessPolicy(
              uid,
              allowedApps: apps,
              permissions: permissions,
            );
          },
          onPickDirectory: (onSelected) async {
            final paths = await showFolderPickerBottomSheet(context);
            if (paths != null && paths.isNotEmpty) {
              for (final path in paths) {
                onSelected(path);
              }
            }
          },
        );
      },
    );
  }
}
