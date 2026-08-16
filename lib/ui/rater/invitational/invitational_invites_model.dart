/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:collection/collection.dart";
import "package:flutter/material.dart";
import "package:shooting_sports_analyst/data/database/analyst_database.dart";
import "package:shooting_sports_analyst/data/database/extensions/application_preferences.dart";
import "package:shooting_sports_analyst/data/database/extensions/invitational_invite_configs.dart";
import "package:shooting_sports_analyst/data/database/match/rating_project_database.dart";
import "package:shooting_sports_analyst/data/database/schema/invitational_invite_config.dart";
import "package:shooting_sports_analyst/data/database/schema/ratings.dart";
import "package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart";
import "package:shooting_sports_analyst/data/ranking/invitational/invitation_match.dart";
import "package:shooting_sports_analyst/data/ranking/invitational/invitational_invite_config.dart";
import "package:shooting_sports_analyst/data/ranking/invitational/invitational_invite_engine.dart";
import "package:shooting_sports_analyst/logger.dart";
import "package:shooting_sports_analyst/util.dart";

final _log = SSALogger("InvitationalInvitesModel");

class InvitationalInvitesModel extends ChangeNotifier {
  InvitationalInvitesModel({
    required this.dataSource,
    AnalystDatabase? db,
  }) : db = db ?? AnalystDatabase();

  final RatingDataSource dataSource;
  final AnalystDatabase db;

  DbRatingProject? project;
  InvitationalInviteConfig config = InvitationalInviteConfig();
  DbInvitationalInviteConfig? savedRecord;
  InvitationalInviteResult? result;
  bool dirty = false;
  bool loading = true;
  String? loadError;
  bool _disposed = false;

  List<RatingGroup> get projectGroups => project?.groups ?? [];
  List<MatchPointer> get matchPointers => project?.matchPointers ?? [];

  Future<void> init() async {
    loading = true;
    _notify();

    final projectIdRes = await dataSource.getProjectId();
    if(projectIdRes.isErr()) {
      loadError = "Could not load rating project.";
      loading = false;
      _notify();
      return;
    }

    project = await db.getRatingProjectById(projectIdRes.unwrap());
    if(project == null) {
      loadError = "Rating project not found.";
      loading = false;
      _notify();
      return;
    }

    if(!project!.dbGroups.isLoaded) {
      await project!.dbGroups.load();
    }

    config.projectName = project!.name;

    final prefs = db.getPreferencesSync();
    final lastId = prefs.lastInvitationalInviteConfigId;
    if(lastId != null) {
      final record = db.getInvitationalInviteConfigSync(lastId);
      if(record != null) {
        final opened = _applySavedRecord(record);
        if(!opened) {
          _log.w("Failed to hydrate last invitational config $lastId");
        }
      }
    }

    loading = false;
    _notify();
  }

  void _notify() {
    if(!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void notifyConfigChanged() {
    dirty = true;
    _notify();
  }

  String? keyForGroup(RatingGroup group) {
    for(final key in config.groupKeys) {
      final found = findRatingGroup(projectGroups, key);
      if(found != null && found.uuid == group.uuid) {
        return key;
      }
    }
    return null;
  }

  bool isGroupSelected(RatingGroup group) {
    return keyForGroup(group) != null;
  }

  void setGroupSelected(RatingGroup group, bool selected) {
    final existingKey = keyForGroup(group);
    if(selected) {
      if(existingKey == null) {
        config.groupKeys.add(group.uuid);
        config.slotsByGroup.putIfAbsent(group.uuid, () => 10);
        if(config.ladySlots) {
          config.reservedLadySlotsByGroup.putIfAbsent(group.uuid, () => 0);
        }
        if(config.juniorSlots) {
          config.reservedJuniorSlotsByGroup.putIfAbsent(group.uuid, () => 0);
        }
        if(config.seniorSlots) {
          config.reservedSeniorSlotsByGroup.putIfAbsent(group.uuid, () => 0);
        }
        if(config.combineJuniorSeniorSlots) {
          config.reservedJuniorSeniorSlotsByGroup.putIfAbsent(group.uuid, () => 0);
        }
      }
    }
    else if(existingKey != null) {
      config.groupKeys.remove(existingKey);
      config.slotsByGroup.remove(existingKey);
      config.reservedLadySlotsByGroup.remove(existingKey);
      config.reservedJuniorSlotsByGroup.remove(existingKey);
      config.reservedSeniorSlotsByGroup.remove(existingKey);
      config.reservedJuniorSeniorSlotsByGroup.remove(existingKey);
    }
    notifyConfigChanged();
  }

  void setGroupSlots(RatingGroup group, int slots) {
    final key = keyForGroup(group) ?? group.uuid;
    if(!config.groupKeys.contains(key)) {
      config.groupKeys.add(key);
    }
    config.slotsByGroup[key] = slots;
    notifyConfigChanged();
  }

  void setGroupLadySlots(RatingGroup group, int slots) {
    final key = keyForGroup(group) ?? group.uuid;
    if(!config.groupKeys.contains(key)) {
      config.groupKeys.add(key);
    }
    config.reservedLadySlotsByGroup[key] = slots;
    notifyConfigChanged();
  }

  void setGroupJuniorSlots(RatingGroup group, int slots) {
    final key = keyForGroup(group) ?? group.uuid;
    if(!config.groupKeys.contains(key)) {
      config.groupKeys.add(key);
    }
    config.reservedJuniorSlotsByGroup[key] = slots;
    notifyConfigChanged();
  }

  void setGroupSeniorSlots(RatingGroup group, int slots) {
    final key = keyForGroup(group) ?? group.uuid;
    if(!config.groupKeys.contains(key)) {
      config.groupKeys.add(key);
    }
    config.reservedSeniorSlotsByGroup[key] = slots;
    notifyConfigChanged();
  }

  void setGroupJuniorSeniorSlots(RatingGroup group, int slots) {
    final key = keyForGroup(group) ?? group.uuid;
    if(!config.groupKeys.contains(key)) {
      config.groupKeys.add(key);
    }
    config.reservedJuniorSeniorSlotsByGroup[key] = slots;
    notifyConfigChanged();
  }

  void setLadySlots(bool value) {
    config.ladySlots = value;
    if(value) {
      for(final key in config.groupKeys) {
        config.reservedLadySlotsByGroup.putIfAbsent(key, () => 0);
      }
    }
    notifyConfigChanged();
  }

  void setJuniorSlots(bool value) {
    config.juniorSlots = value;
    if(value) {
      for(final key in config.groupKeys) {
        config.reservedJuniorSlotsByGroup.putIfAbsent(key, () => 0);
      }
    }
    else {
      config.combineJuniorSeniorSlots = false;
    }
    notifyConfigChanged();
  }

  void setSeniorSlots(bool value) {
    config.seniorSlots = value;
    if(value) {
      for(final key in config.groupKeys) {
        config.reservedSeniorSlotsByGroup.putIfAbsent(key, () => 0);
      }
    }
    else {
      config.combineJuniorSeniorSlots = false;
    }
    notifyConfigChanged();
  }

  void setCombineJuniorSeniorSlots(bool value) {
    config.combineJuniorSeniorSlots = value;
    if(value) {
      for(final key in config.groupKeys) {
        config.reservedJuniorSeniorSlotsByGroup.putIfAbsent(key, () => 0);
      }
    }
    notifyConfigChanged();
  }

  bool get sportHasJuniorCategories =>
    project?.sport.ageCategories.values.any((c) => c.isJunior) ?? false;

  bool get sportHasSeniorCategories =>
    project?.sport.ageCategories.values.any((c) => c.isSenior) ?? false;

  List<String> unresolvedGroupKeys() {
    return config.groupKeys.where((key) => findRatingGroup(projectGroups, key) == null).toList();
  }

  String labelForSourceId(String id) {
    final pointer = matchPointers.where((p) => p.sourceIds.contains(id)).firstOrNull;
    return pointer?.name ?? id;
  }

  InvitationalInviteCompatibility compatibility() {
    return config.checkCompatibility(
      groups: projectGroups,
      matchPointers: matchPointers,
    );
  }

  void addFinishOrderRule() {
    config.invitationMatches.add(InvitationMatch.topN(topN: 1));
    notifyConfigChanged();
  }

  void removeFinishOrderRule(InvitationMatch rule) {
    config.invitationMatches.remove(rule);
    notifyConfigChanged();
  }

  void addExcludedGroupsRule() {
    config.excludedGroups.add(ExcludedGroupsRule());
    notifyConfigChanged();
  }

  void removeExcludedGroupsRule(ExcludedGroupsRule rule) {
    config.excludedGroups.remove(rule);
    notifyConfigChanged();
  }

  bool _applySavedRecord(DbInvitationalInviteConfig record) {
    final hydrated = record.hydrate();
    if(hydrated.isErr()) {
      return false;
    }
    config = hydrated.unwrap();
    if(project != null) {
      config.projectName = project!.name;
    }
    savedRecord = record;
    dirty = false;
    result = null;
    return true;
  }

  Future<Result<void, StringError>> open(DbInvitationalInviteConfig record) async {
    if(!_applySavedRecord(record)) {
      return Result.err(StringError("Failed to load config \"${record.name}\"."));
    }
    _remember(record);
    _notify();
    return Result.ok(null);
  }

  void refreshSavedRecord() {
    if(savedRecord == null) {
      return;
    }
    if(db.getInvitationalInviteConfigSync(savedRecord!.id) == null) {
      savedRecord = null;
      _notify();
    }
  }

  Future<Result<void, StringError>> save({String? name}) async {
    final saveName = name ?? savedRecord?.name;
    if(saveName == null || saveName.trim().isEmpty) {
      return Result.err(StringError("Config name is required."));
    }

    final now = DateTime.now();
    final record = savedRecord ?? DbInvitationalInviteConfig();
    record.name = saveName.trim();
    record.encodeConfig(config);
    record.updated = now;
    record.lastUsedProjectId = project?.id;
    if(savedRecord == null) {
      record.created = now;
    }

    final id = await db.saveInvitationalInviteConfig(record);
    record.id = id;
    savedRecord = record;
    dirty = false;
    _remember(record);
    _notify();
    return Result.ok(null);
  }

  Future<void> delete(DbInvitationalInviteConfig record) async {
    await db.deleteInvitationalInviteConfig(record.id);
    if(savedRecord?.id == record.id) {
      savedRecord = null;
    }
    final prefs = db.getPreferencesSync();
    if(prefs.lastInvitationalInviteConfigId == record.id) {
      prefs.lastInvitationalInviteConfigId = null;
      db.savePreferencesSync(prefs);
    }
    _notify();
  }

  Future<Result<List<String>, StringError>> importToml(String toml) async {
    final parsed = InvitationalInviteConfig.parseToml(toml);
    if(parsed.isErr()) {
      return Result.err(parsed.unwrapErr());
    }
    final result = parsed.unwrap();
    config = result.config;
    if(project != null) {
      config.projectName = project!.name;
    }
    savedRecord = null;
    dirty = true;
    this.result = null;
    _notify();
    return Result.ok(result.warnings);
  }

  String exportToml() {
    return config.toToml();
  }

  Future<Result<InvitationalInviteResult, StringError>> generate({
    InvitationalInviteProgressCallback? onProgress,
  }) async {
    if(project == null) {
      return Result.err(StringError("Rating project is not loaded."));
    }
    final engine = InvitationalInviteEngine();
    final generated = await engine.generate(
      db: db,
      project: project!,
      config: config,
      onProgress: onProgress,
    );
    if(generated.isOk()) {
      result = generated.unwrap();
      _notify();
    }
    return generated;
  }

  void _remember(DbInvitationalInviteConfig record) {
    final prefs = db.getPreferencesSync();
    prefs.lastInvitationalInviteConfigId = record.id;
    db.savePreferencesSync(prefs);
  }
}
