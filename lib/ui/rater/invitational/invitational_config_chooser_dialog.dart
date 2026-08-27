/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:flutter/material.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/extensions/invitational_invite_configs.dart";
import "package:shooting_sports_analyst/data/database/schema/invitational_invite_config.dart";
import "package:shooting_sports_analyst/ui/widget/dialog/confirm_dialog.dart";
import "package:shooting_sports_analyst/util.dart";

class InvitationalConfigChooserDialog extends StatefulWidget {
  const InvitationalConfigChooserDialog({super.key, required this.db});

  final AnalystDatabase db;

  static Future<DbInvitationalInviteConfig?> show(
    BuildContext context, {
    required AnalystDatabase db,
    bool useRootNavigator = false,
    bool barrierDismissible = false,
  }) {
    return showDialog<DbInvitationalInviteConfig>(
      context: context,
      useRootNavigator: useRootNavigator,
      builder: (context) => InvitationalConfigChooserDialog(db: db),
    );
  }

  @override
  State<InvitationalConfigChooserDialog> createState() => _InvitationalConfigChooserDialogState();
}

class _InvitationalConfigChooserDialogState extends State<InvitationalConfigChooserDialog> {
  late List<DbInvitationalInviteConfig> _configs;

  @override
  void initState() {
    super.initState();
    _configs = widget.db.getInvitationalInviteConfigsSync();
  }

  Future<void> _reload() async {
    setState(() {
      _configs = widget.db.getInvitationalInviteConfigsSync();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Open Invitational Config"),
      content: SizedBox(
        width: 500,
        height: 400,
        child: _configs.isEmpty
            ? const Center(child: Text("No saved configs."))
            : ListView.separated(
                itemCount: _configs.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final config = _configs[index];
                  return ListTile(
                    title: Text(config.name),
                    subtitle: Text("Updated ${programmerYmdFormat.format(config.updated)}"),
                    onTap: () => Navigator.of(context).pop(config),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final confirmed = await ConfirmDialog.show(
                          context,
                          title: "Delete Config",
                          content: Text("Delete \"${config.name}\"?"),
                          positiveButtonLabel: "DELETE",
                          negativeButtonLabel: "CANCEL",
                        );
                        if(confirmed == true) {
                          await widget.db.deleteInvitationalInviteConfig(config.id);
                          await _reload();
                        }
                      },
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("CANCEL"),
        ),
      ],
    );
  }
}
