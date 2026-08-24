/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "package:shooting_sports_analyst/config/config.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/help/entries/invitational_invites_help.dart";
import "package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart";
import "package:shooting_sports_analyst/data/ranking/invitational/invitational_invite_config.dart";
import "package:shooting_sports_analyst/html_or/html_or.dart";
import "package:shooting_sports_analyst/ui/empty_scaffold.dart";
import "package:shooting_sports_analyst/ui/rater/invitational/excluded_groups_editor.dart";
import "package:shooting_sports_analyst/ui/rater/invitational/invitation_match_editor.dart";
import "package:shooting_sports_analyst/ui/rater/invitational/invitational_config_chooser_dialog.dart";
import "package:shooting_sports_analyst/ui/rater/invitational/invitational_invites_model.dart";
import "package:shooting_sports_analyst/ui/rater/invitational/invite_results_table.dart";
import "package:shooting_sports_analyst/ui/rater/invitational/numeric_fields.dart";
import "package:shooting_sports_analyst/ui/widget/dialog/confirm_dialog.dart";
import "package:shooting_sports_analyst/ui/widget/dialog/loading_dialog.dart";
import "package:shooting_sports_analyst/ui/widget/text_input_dialog.dart";
import "package:shooting_sports_analyst/util.dart";

enum _FileMenu {
  open,
  save,
  saveAs,
  importToml,
  exportToml,
}

class InvitationalInvitesPage extends StatefulWidget {
  const InvitationalInvitesPage({super.key, required this.dataSource});

  final RatingDataSource dataSource;

  @override
  State<InvitationalInvitesPage> createState() => _InvitationalInvitesPageState();
}

class _InvitationalInvitesPageState extends State<InvitationalInvitesPage> with SingleTickerProviderStateMixin {
  late InvitationalInvitesModel _model;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _model = InvitationalInvitesModel(dataSource: widget.dataSource);
    _model.init();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _model.dispose();
    super.dispose();
  }

  String get _title {
    final name = _model.savedRecord?.name;
    if(name == null || name.isEmpty) {
      return "Invitational Invites";
    }
    return "Invitational Invites — $name${_model.dirty ? " *" : ""}";
  }

  Future<void> _handleFileMenu(_FileMenu item) async {
    switch(item) {
      case _FileMenu.open:
        final chosen = await InvitationalConfigChooserDialog.show(context, db: _model.db);
        if(chosen != null) {
          final opened = await _model.open(chosen);
          if(opened.isErr() && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(opened.unwrapErr().message)));
          }
        }
        else {
          _model.refreshSavedRecord();
        }
      case _FileMenu.save:
        await _save(saveAs: false);
      case _FileMenu.saveAs:
        await _save(saveAs: true);
      case _FileMenu.importToml:
        final contents = await HtmlOr.pickAndReadFileNow();
        if(contents == null) {
          return;
        }
        final imported = await _model.importToml(contents);
        if(!mounted) {
          return;
        }
        if(imported.isErr()) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(imported.unwrapErr().message)));
          return;
        }
        final warnings = imported.unwrap();
        if(warnings.isNotEmpty) {
          await _showMessageDialog("Import Warnings", warnings.join("\n"));
        }
      case _FileMenu.exportToml:
        try {
          final toml = _model.exportToml();
          final filename = "${(_model.savedRecord?.name ?? "invitational-invites").safeFilename()}.toml";
          await HtmlOr.saveFile(filename, toml);
        }
        catch(e) {
          if(mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to export TOML: $e")));
          }
        }
    }
  }

  Future<void> _save({required bool saveAs}) async {
    String? name = _model.savedRecord?.name;
    if(saveAs || name == null || name.isEmpty) {
      name = await TextInputDialog.show(
        context,
        title: "Config Name",
        initialValue: name,
      );
      if(name == null || name.isEmpty) {
        return;
      }
    }
    final saved = await _model.save(name: name);
    if(saved.isErr() && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(saved.unwrapErr().message)));
    }
  }

  Future<void> _generate() async {
    final compatibility = _model.compatibility();
    if(compatibility.hasIssues) {
      final proceed = await ConfirmDialog.show(
        context,
        title: "Config Does Not Fully Match This Project",
        content: Text(_compatibilityMessage(compatibility)),
        positiveButtonLabel: "GENERATE ANYWAY",
        negativeButtonLabel: "CANCEL",
      );
      if(proceed != true) {
        return;
      }
    }

    final progress = ProgressModel();
    final future = _model.generate(
      onProgress: (current, total) {
        progress.total = total;
        progress.current = current;
      },
    );
    final generated = await LoadingDialog.show(
      context: context,
      waitOn: future,
      title: "Generating invitations...",
      progressProvider: progress,
    );
    if(!mounted || generated == null) {
      return;
    }
    if(generated.isErr()) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(generated.unwrapErr().message)));
      return;
    }
    final result = generated.unwrap();
    _tabController.animateTo(1);
    if(result.warnings.isNotEmpty) {
      await _showMessageDialog("Generation Warnings", result.warnings.join("\n"));
    }
  }

  Future<void> _exportCsv() async {
    final result = _model.result;
    if(result == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Generate invitations before exporting CSV.")));
      return;
    }
    final filename = "${(_model.savedRecord?.name ?? "invitations").safeFilename()}.csv";
    await HtmlOr.saveFile(filename, result.toCsv());
  }

  String _compatibilityMessage(InvitationalInviteCompatibility compatibility) {
    final lines = <String>[];
    if(compatibility.unresolvedGroupKeys.isNotEmpty) {
      lines.add("Unresolved groups:\n${compatibility.unresolvedGroupKeys.map((k) => "  $k").join("\n")}");
    }
    if(compatibility.unresolvedSourceIds.isNotEmpty) {
      lines.add("Match source IDs not in this project:\n${compatibility.unresolvedSourceIds.map((k) => "  $k").join("\n")}");
    }
    lines.add("\nGeneration will skip unresolved groups and IDs.");
    return lines.join("\n\n");
  }

  Future<void> _showMessageDialog(String title, String message) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(child: Text(message)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _model,
      child: Consumer<InvitationalInvitesModel>(
        builder: (context, model, _) {
          return EmptyScaffold(
            title: _title,
            helpTopicId: invitationalInvitesHelpId,
            operationInProgress: model.loading,
            actions: [
              Tooltip(
                message: "Generate invitations",
                child: IconButton(
                  icon: const Icon(Icons.play_arrow),
                  onPressed: model.loading || model.project == null ? null : _generate,
                ),
              ),
              Tooltip(
                message: "Export CSV",
                child: IconButton(
                  icon: const Icon(Icons.table_view),
                  onPressed: model.result == null ? null : _exportCsv,
                ),
              ),
              PopupMenuButton<_FileMenu>(
                onSelected: _handleFileMenu,
                itemBuilder: (context) => [
                  const PopupMenuItem(value: _FileMenu.open, child: Text("Open")),
                  const PopupMenuItem(value: _FileMenu.save, child: Text("Save")),
                  const PopupMenuItem(value: _FileMenu.saveAs, child: Text("Save As")),
                  const PopupMenuItem(value: _FileMenu.importToml, child: Text("Import TOML")),
                  const PopupMenuItem(value: _FileMenu.exportToml, child: Text("Export TOML")),
                ],
              ),
            ],
            child: _buildBody(model),
          );
        },
      ),
    );
  }

  Widget _buildBody(InvitationalInvitesModel model) {
    if(model.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if(model.loadError != null) {
      return Center(child: Text(model.loadError!));
    }

    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: "Config"),
              Tab(text: "Results"),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _ConfigEditor(model: model),
              model.result == null
                  ? const Center(child: Text("Generate invitations to see results."))
                  : InviteResultsTable(result: model.result!, dataSource: widget.dataSource),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConfigEditor extends StatelessWidget {
  const _ConfigEditor({required this.model});

  final InvitationalInvitesModel model;

  @override
  Widget build(BuildContext context) {
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    final config = model.config;
    final unresolved = model.unresolvedGroupKeys();
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 1280 * uiScaleFactor),
        child: ListView(
          padding: EdgeInsets.all(16 * uiScaleFactor),
          children: [
            Text("General", style: Theme.of(context).textTheme.titleLarge),
            CheckboxListTile(
              title: const Text("Reserved Lady Slots"),
              value: config.ladySlots,
              onChanged: (value) => model.setLadySlots(value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if(model.sportHasJuniorCategories || config.juniorSlots)
              CheckboxListTile(
                title: const Text("Reserved Junior Slots"),
                subtitle: const Text("Age categories whose oldest competitors are 21 or under."),
                value: config.juniorSlots,
                onChanged: (value) => model.setJuniorSlots(value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            if(model.sportHasSeniorCategories || config.seniorSlots)
              CheckboxListTile(
                title: const Text("Reserved Senior Slots"),
                subtitle: const Text("Age categories whose youngest competitors are 50 or over."),
                value: config.seniorSlots,
                onChanged: (value) => model.setSeniorSlots(value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            // if(config.juniorSlots && config.seniorSlots)
            //   CheckboxListTile(
            //     title: const Text("Combine Junior And Senior Slots"),
            //     subtitle: const Text("Treat junior and senior reserved slots as one shared pool."),
            //     value: config.combineJuniorSeniorSlots,
            //     onChanged: (value) => model.setCombineJuniorSeniorSlots(value ?? false),
            //   ),
            CheckboxListTile(
              title: const Text("Multiple Division Rating Qualification"),
              subtitle: const Text("If a shooter already has an invite, also credit other selected groups by rating."),
              value: config.multipleDivisionRatingQualification,
              onChanged: (value) {
                config.multipleDivisionRatingQualification = value ?? false;
                model.notifyConfigChanged();
              },
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              title: const Text("Combined Scoring For Multi-Division Groups"),
              subtitle: const Text("If checked, invitations for multi-division groups will use combined scoring, not per-division scoring."),
              value: config.combinedScoringForMultiDivisionGroups,
              onChanged: (value) {
                config.combinedScoringForMultiDivisionGroups = value ?? false;
                model.notifyConfigChanged();
              },
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              title: const Text("Include Emails"),
              value: config.includeEmails,
              onChanged: (value) {
                config.includeEmails = value ?? false;
                model.notifyConfigChanged();
              },
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: DoubleTextField(
                value: config.takeRate,
                width: 150 * uiScaleFactor,
                label: "Take Rate",
                onChanged: (value) {
                  config.takeRate = value;
                  model.notifyConfigChanged();
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(config.activeSince != null
                    ? "Active since ${programmerYmdFormat.format(config.activeSince!)}"
                    : "No activity cutoff"),
                SizedBox(width: 8 * uiScaleFactor),
                TextButton(
                  child: const Text("SET DATE"),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: config.activeSince ?? DateTime.now(),
                      firstDate: DateTime(2010),
                      lastDate: DateTime.now(),
                    );
                    if(picked != null) {
                      config.activeSince = picked;
                      model.notifyConfigChanged();
                    }
                  },
                ),
                if(config.activeSince != null)
                  TextButton(
                    child: const Text("CLEAR"),
                    onPressed: () {
                      config.activeSince = null;
                      model.notifyConfigChanged();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text("Take rate is the expected accept rate. Maximum invites per group are slots / take rate.",
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 24),
            Text("Groups And Slots", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            for(final group in model.projectGroups)
              _GroupSlotRow(model: model, group: group),
            if(unresolved.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  "Unresolved group keys: ${unresolved.join(", ")}",
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: Text("Excluded Groups", style: Theme.of(context).textTheme.titleLarge)),
                TextButton.icon(
                  onPressed: model.addExcludedGroupsRule,
                  icon: const Icon(Icons.add),
                  label: const Text("Add Rule"),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if(config.excludedGroups.isEmpty)
              const Text("No excluded-group rules."),
            for(final rule in config.excludedGroups)
              ExcludedGroupsEditor(
                key: ObjectKey(rule),
                rule: rule,
                projectGroups: model.projectGroups,
                matchPointers: model.matchPointers,
                onChanged: model.notifyConfigChanged,
                onDelete: () => model.removeExcludedGroupsRule(rule),
              ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: Text("Finish-Order Rules", style: Theme.of(context).textTheme.titleLarge)),
                TextButton.icon(
                  onPressed: model.addFinishOrderRule,
                  icon: const Icon(Icons.add),
                  label: const Text("Add Rule"),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text("Higher-priority rules run first. Within a priority, matches are processed newest first.",
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            if(config.invitationMatches.isEmpty)
              const Text("No finish-order rules."),
            for(final rule in config.invitationMatches)
              InvitationMatchEditor(
                key: ObjectKey(rule),
                rule: rule,
                matchPointers: model.matchPointers,
                ladySlots: config.ladySlots,
                juniorSlots: config.juniorSlots,
                seniorSlots: config.seniorSlots,
                onChanged: model.notifyConfigChanged,
                onDelete: () => model.removeFinishOrderRule(rule),
              ),
          ],
        ),
      ),
    );
  }
}

class _GroupSlotRow extends StatelessWidget {
  const _GroupSlotRow({required this.model, required this.group});

  final InvitationalInvitesModel model;
  final RatingGroup group;

  @override
  Widget build(BuildContext context) {
    final uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    final selected = model.isGroupSelected(group);
    final key = model.keyForGroup(group) ?? group.uuid;
    final slots = model.config.slotsByGroup[key] ?? 10;
    final ladySlots = model.config.reservedLadySlotsByGroup[key] ?? 0;
    final juniorSlots = model.config.reservedJuniorSlotsByGroup[key] ?? 0;
    final seniorSlots = model.config.reservedSeniorSlotsByGroup[key] ?? 0;
    final juniorSeniorSlots = model.config.reservedJuniorSeniorSlotsByGroup[key] ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 220 * uiScaleFactor,
            child: CheckboxListTile(
              value: selected,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(group.uiLabel),
              onChanged: (value) => model.setGroupSelected(group, value ?? false),
            ),
          ),
          if(selected) ...[
            IntTextField(
              value: slots,
              label: "Slots",
              onChanged: (value) => model.setGroupSlots(group, value),
            ),
            if(model.config.ladySlots) ...[
              SizedBox(width: 12 * uiScaleFactor),
              IntTextField(
                value: ladySlots,
                label: "Lady Slots",
                width: 100 * uiScaleFactor,
                onChanged: (value) => model.setGroupLadySlots(group, value),
              ),
            ],
            if(model.config.combineAgeSlots) ...[
              SizedBox(width: 12 * uiScaleFactor),
              IntTextField(
                value: juniorSeniorSlots,
                label: "Jr/Sr Slots",
                width: 100 * uiScaleFactor,
                onChanged: (value) => model.setGroupJuniorSeniorSlots(group, value),
              ),
            ]
            else ...[
              if(model.config.juniorSlots) ...[
                SizedBox(width: 12 * uiScaleFactor),
                IntTextField(
                  value: juniorSlots,
                  label: "Junior Slots",
                  width: 110 * uiScaleFactor,
                  onChanged: (value) => model.setGroupJuniorSlots(group, value),
                ),
              ],
              if(model.config.seniorSlots) ...[
                SizedBox(width: 12 * uiScaleFactor),
                IntTextField(
                  value: seniorSlots,
                  label: "Senior Slots",
                  width: 110 * uiScaleFactor,
                  onChanged: (value) => model.setGroupSeniorSlots(group, value),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }
}
