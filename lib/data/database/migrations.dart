/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

//ignore_for_file: unused_import

import 'package:isar_community/isar.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/extensions/prediction_game.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_heat.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/algorithm_prediction.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/prediction_set.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration_mapping.dart';
import 'package:shooting_sports_analyst/data/database/schema/prediction_game/wager.dart';
import 'package:shooting_sports_analyst/data/ranking/prediction/match_prediction.dart';
import 'package:shooting_sports_analyst/logger.dart';

// ignore: unused_element
final _log = SSALogger("Migrations");

// Migrations from 2025-01-30: 32-bit to 64-bit hashed/combined-hashed IDs.
// Retained for posterity.

// Future<void> migrateMatchPrepIds() async {
//   var db = AnalystDatabase();
//   // Get all match preps.
//   var matchPreps = await MatchPrepDatabase(db).getMatchPreps();

//   // Save all old IDs for future deletion.
//   Map<int, MatchPrep> oldIdsToMatchPreps = {};
//   for(var matchPrep in matchPreps) {
//     var oldPrep = await db.isar.matchPreps.get(matchPrep.oldId);
//     if(oldPrep != null) {
//       matchPrep.futureMatch.value = oldPrep.futureMatch.value;
//       matchPrep.ratingProject.value = oldPrep.ratingProject.value;
//       matchPrep.predictionSets.addAll(oldPrep.predictionSets);
//       matchPrep.games.addAll(oldPrep.games);
//     }
//     oldIdsToMatchPreps[matchPrep.oldId] = matchPrep;
//   }

//   // Put all match preps to save copies with new IDs.
//   for(var matchPrep in matchPreps) {
//     await db.saveMatchPrep(matchPrep);
//   }

//   var games = await db.getAllPredictionGames();
//   for(var game in games) {
//     var matchPreps = game.matchPreps.toList();

//     await db.isar.writeTxn(() async {
//       game.matchPreps.clear();
//       await game.matchPreps.save();
//       game.matchPreps.addAll(matchPreps);
//       await game.matchPreps.save();
//     });

//     for(var wager in game.wagers) {
//       var matchPrep = oldIdsToMatchPreps[wager.matchPrep.value!.oldId];
//       if(matchPrep != null) {
//         wager.matchPrep.value = matchPrep;
//         await db.isar.writeTxn(() async {
//           await wager.matchPrep.save();
//         });
//       }
//     }
//   }

//   var predictionSets = await db.isar.predictionSets.where().anyId().findAll();
//   for(var predictionSet in predictionSets) {
//     var matchPrep = oldIdsToMatchPreps[predictionSet.matchPrep.value!.oldId];
//     if(matchPrep != null) {
//       predictionSet.matchPrep.value = matchPrep;
//       await db.isar.writeTxn(() async {
//         await predictionSet.matchPrep.save();
//       });
//     }
//   }

//   await db.isar.writeTxn(() async {
//     for(var oldId in oldIdsToMatchPreps.keys) {
//       await db.isar.matchPreps.where().idEqualTo(oldId).deleteAll();
//     }
//   });
// }

// Future<void> migrateMatchRegistrationMappingIds() async {
//   var db = AnalystDatabase();
//   var mappings = await db.isar.matchRegistrationMappings.where().anyId().findAll();
//   Map<int, MatchRegistrationMapping> oldIdsToRegistrations = {};
//   for(var registration in mappings) {
//     oldIdsToRegistrations[registration.oldId] = registration;
//     db.isar.writeTxnSync(() {
//       db.isar.matchRegistrationMappings.putSync(registration);
//     });
//   }

//    var futureMatches = await db.isar.futureMatchs.where().anyId().findAll();
//    for(var futureMatch in futureMatches) {
//     var mappings = futureMatch.mappings.toList();
//     await db.isar.writeTxn(() async {
//       futureMatch.mappings.clear();
//       await futureMatch.mappings.save();
//       futureMatch.mappings.addAll(mappings);
//       await futureMatch.mappings.save();
//     });
//    }

//    await db.isar.writeTxn(() async {
//     for(var oldId in oldIdsToRegistrations.keys) {
//       await db.isar.matchRegistrationMappings.where().idEqualTo(oldId).deleteAll();
//     }
//   });
// }

// Future<void> migrateMatchRegistrationIds() async {
//   var db = AnalystDatabase();
//   var registrations = await db.isar.matchRegistrations.where().anyId().findAll();
//   Map<int, MatchRegistration> oldIdsToRegistrations = {};
//   for(var registration in registrations) {
//     oldIdsToRegistrations[registration.oldId] = registration;
//     db.isar.writeTxnSync(() {
//       db.isar.matchRegistrations.putSync(registration);
//     });
//   }

//   var futureMatches = await db.isar.futureMatchs.where().anyId().findAll();
//   for(var futureMatch in futureMatches) {
//     var registrations = futureMatch.registrations.toList();
//     await db.isar.writeTxn(() async {
//       futureMatch.registrations.clear();
//       await futureMatch.registrations.save();
//       futureMatch.registrations.addAll(registrations);
//       await futureMatch.registrations.save();
//     });
//   }

//   await db.isar.writeTxn(() async {
//     for(var oldId in oldIdsToRegistrations.keys) {
//       await db.isar.matchRegistrations.where().idEqualTo(oldId).deleteAll();
//     }
//   });
// }

// // Migrate both prediction set and algorithm prediction ids to 64-bit.
// Future<void> migratePredictionSetIds() async {
//   var db = AnalystDatabase();
//   var predictionSets = await db.isar.predictionSets.where().anyId().findAll();

//   Map<int, DbAlgorithmPrediction> oldIdsToAlgorithmPredictions = {};
//   var algorithmPredictions = await db.isar.dbAlgorithmPredictions.where().anyId().findAll();
//   for(var algorithmPrediction in algorithmPredictions) {
//     oldIdsToAlgorithmPredictions[algorithmPrediction.oldId] = algorithmPrediction;
//     var oldAlgorithmPrediction = db.isar.dbAlgorithmPredictions.getSync(algorithmPrediction.oldId);
//     if(oldAlgorithmPrediction != null) {
//       algorithmPrediction.project.value = oldAlgorithmPrediction.project.value;
//       algorithmPrediction.group.value = oldAlgorithmPrediction.group.value;
//       algorithmPrediction.rating.value = oldAlgorithmPrediction.rating.value;
//     }
//     db.isar.writeTxnSync(() {
//       db.isar.dbAlgorithmPredictions.putSync(algorithmPrediction);
//     });
//   }

//   Map<int, PredictionSet> oldIdsToPredictionSets = {};
//   for(var predictionSet in predictionSets) {
//     oldIdsToPredictionSets[predictionSet.oldId] = predictionSet;
//     db.isar.writeTxnSync(() {
//       var oldPredictionSet = db.isar.predictionSets.getSync(predictionSet.oldId);
//       predictionSet.matchPrep.value = oldPredictionSet!.matchPrep.value;
//       List<DbAlgorithmPrediction> updatedPredictions = [];
//       for(var algorithmPrediction in oldPredictionSet.algorithmPredictions) {
//         var oldAlgorithmPrediction = oldIdsToAlgorithmPredictions[algorithmPrediction.oldId];
//         if(oldAlgorithmPrediction != null) {
//           updatedPredictions.add(oldAlgorithmPrediction);
//         }
//       }
//       predictionSet.algorithmPredictions.clear();
//       predictionSet.algorithmPredictions.addAll(oldPredictionSet.algorithmPredictions);

//       db.isar.predictionSets.putSync(predictionSet);
//       predictionSet.algorithmPredictions.saveSync();
//     });
//   }

//   var wagers = await db.isar.dbWagers.where().anyId().findAll();
//   for(var wager in wagers) {
//     var newSet = db.isar.predictionSets.getSync(wager.predictionSet.value!.id);
//     wager.predictionSet.value = newSet;
//     db.isar.writeTxnSync(() {
//       wager.predictionSet.saveSync();
//     });
//   }

//   db.isar.writeTxnSync(() {
//     for(var predictionSet in oldIdsToPredictionSets.keys) {
//       db.isar.predictionSets.where().idEqualTo(predictionSet).deleteAllSync();
//     }
//     for(var algorithmPrediction in oldIdsToAlgorithmPredictions.keys) {
//       db.isar.dbAlgorithmPredictions.where().idEqualTo(algorithmPrediction).deleteAllSync();
//     }
//   });
// }

// Future<void> migrateStandaloneDbMatchEntryIds() async {
//   var db = AnalystDatabase();
//   var matchEntries = await db.isar.standaloneDbMatchEntrys.where().anyDbId().findAll();
//   for(var matchEntry in matchEntries) {
//     db.isar.writeTxnSync(() {
//       db.isar.standaloneDbMatchEntrys.putSync(matchEntry);
//     });
//   }

//   var matches = await db.isar.dbShootingMatchs.where().anyId().findAll();
//   for(var match in matches) {
//     if(match.shootersStoredSeparately) {
//       var entries = match.shooterLinks.toList();
//       await db.isar.writeTxn(() async {
//         match.shooterLinks.clear();
//         await match.shooterLinks.save();
//         match.shooterLinks.addAll(entries);
//         await match.shooterLinks.save();
//       });
//     }
//   }
// }

// Future<void> migrateMatchHeatIds() async {
//   var db = AnalystDatabase();
//   var matchHeats = await db.isar.matchHeats.where().anyId().findAll();
//   for(var matchHeat in matchHeats) {
//     db.isar.writeTxnSync(() {
//       db.isar.matchHeats.where().idEqualTo(matchHeat.oldId).deleteAllSync();
//       db.isar.matchHeats.where().idEqualTo(matchHeat.id).deleteAllSync();
//       db.isar.matchHeats.putSync(matchHeat);
//     });
//   }
// }