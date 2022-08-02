import 'package:flutter/foundation.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/practiscore_parser.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo_rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/multiplayer_elo_rater.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/multiplayer_percent_elo_rater.dart';
import 'package:uspsa_result_viewer/ui/filter_dialog.dart';

var castlewoodMatchUrls = [
  "https://practiscore.com/results/new/bea1d67c-3176-48f2-9905-77c8d2673a70",
  "https://practiscore.com/results/new/08f3d157-aeaf-422f-b9a7-d342051644c5",
  "https://practiscore.com/results/new/ddacc20c-61e5-4e5c-be7a-2b54fcb3892d",
  "https://practiscore.com/results/new/a0c94340-ecc6-4016-a3ab-cee1b7387357",
  "https://practiscore.com/results/new/8628231c-4235-4713-90f3-311388dfbaef",
  "https://practiscore.com/results/new/94fd96ad-1c7f-49bf-8b75-71b14fc12d1b",
  "https://practiscore.com/results/new/8d3bdcef-4523-4d5a-b310-73b1acc148f9",
  "https://practiscore.com/results/new/4906a64e-8c57-4587-9b0a-ccee719a431a",
  "https://practiscore.com/results/new/35e478ec-e9b3-4a13-97f6-1c6913e1c5c4",
  "https://practiscore.com/results/new/2579c6db-1e4c-4448-af55-be0b1bf0edde",
  "https://practiscore.com/results/new/e65b8840-e81d-4d40-bc46-26ad988d3ddd",
  "https://practiscore.com/results/new/c1f4854e-7684-4c11-a883-e9742aa1124d",
  "https://practiscore.com/results/new/f08f37a2-db1b-4f29-b1b9-90e065a4b0a4",
  "https://practiscore.com/results/new/752141a7-e339-49ee-bd8e-09f3a6b1cf8b",
  "https://practiscore.com/results/new/d8cb8ed0-d4ab-4190-b9df-49908e481a17",
  "https://practiscore.com/results/new/32689df8-309f-47b9-b51b-21b993ed2311",
].reversed.toList();

var outEastMatchUrls = [ // Cantrell's stomping grounds
  "https://www.practiscore.com/results/new/174787",
  "https://www.practiscore.com/results/new/171773",
  "https://www.practiscore.com/results/new/167848",
  "https://www.practiscore.com/results/new/165072",
  "https://www.practiscore.com/results/new/162442",
  "https://www.practiscore.com/results/new/174467",
  "https://www.practiscore.com/results/new/171551",
  "https://www.practiscore.com/results/new/164866",
  "https://www.practiscore.com/results/new/162099",
  "https://www.practiscore.com/results/new/175382",
  "https://www.practiscore.com/results/new/169252",
  "https://www.practiscore.com/results/new/165572",
  "https://www.practiscore.com/results/new/162879",
  "https://www.practiscore.com/results/new/173148",
  "https://www.practiscore.com/results/new/169883",
  "https://www.practiscore.com/results/new/163497",
  "https://www.practiscore.com/results/new/172204",
  "https://www.practiscore.com/results/new/169150",
  "https://www.practiscore.com/results/new/165475",
  "https://www.practiscore.com/results/new/162753",
  "https://www.practiscore.com/results/new/160329",
  "https://www.practiscore.com/results/new/170692",
  "https://www.practiscore.com/results/new/164208",
  "https://www.practiscore.com/results/new/175412",
  "https://www.practiscore.com/results/new/172327",
  "https://www.practiscore.com/results/new/165587",
  "https://www.practiscore.com/results/new/162899",
  "https://www.practiscore.com/results/new/176161",
  "https://www.practiscore.com/results/new/173711",
  "https://www.practiscore.com/results/new/170632",
  "https://www.practiscore.com/results/new/167548",
  "https://www.practiscore.com/results/new/164174",
];

var areaMatchUrls = [ // area matches
  "https://www.practiscore.com/results/new/169680",
  "https://www.practiscore.com/results/new/143211",
  "https://www.practiscore.com/results/new/119324",
  "https://www.practiscore.com/results/new/84701",
  "https://www.practiscore.com/results/new/57037",
  "https://www.practiscore.com/results/new/150803",
  "https://www.practiscore.com/results/new/122157",
  "https://www.practiscore.com/results/new/96911",
  "https://www.practiscore.com/results/new/69654",
  "https://www.practiscore.com/results/new/142725",
  "https://www.practiscore.com/results/new/113573",
  "https://www.practiscore.com/results/new/88452",
  "https://www.practiscore.com/results/new/63305",
  "https://www.practiscore.com/results/new/148135",
  "https://www.practiscore.com/results/new/117974",
  "https://www.practiscore.com/results/new/87404",
  "https://www.practiscore.com/results/new/65924",
  "https://www.practiscore.com/results/new/175816",
  "https://www.practiscore.com/results/new/91448",
  "https://www.practiscore.com/results/new/146707",
  "https://www.practiscore.com/results/new/117346",
  "https://www.practiscore.com/results/new/62672",
  "https://www.practiscore.com/results/new/163972",
  "https://www.practiscore.com/results/new/131991",
  "https://www.practiscore.com/results/new/78750",
  "https://www.practiscore.com/results/new/54465",
  "https://www.practiscore.com/results/new/139302",
  "https://www.practiscore.com/results/new/118650",
  "https://www.practiscore.com/results/new/84766",
  "https://www.practiscore.com/results/new/59688",
  "https://www.practiscore.com/results/new/145355",
  "https://www.practiscore.com/results/new/115551",
  "https://www.practiscore.com/results/new/90343",
  "https://www.practiscore.com/results/new/64849",
];

var singleMatchUrl = [
  "https://practiscore.com/results/new/163576", // GPGC April 1
];

void dumpRatings() async {
  // var matchUrls = [ // Western PA
  //   "https://practiscore.com/results/new/161142", // Gem City March
  //   "https://practiscore.com/results/new/162898", // EHPSA March
  //
  //   "https://practiscore.com/results/new/163678", // Gem City April
  //   "https://practiscore.com/results/new/163757", // Pardoe April
  //   "https://practiscore.com/results/new/163576", // GPGC April 1
  //   "https://practiscore.com/results/new/164215", // LCSA April
  //   "https://practiscore.com/results/new/165480", // Castlewood April
  //   "https://practiscore.com/results/new/165554", // EHPSA April
  //   "https://practiscore.com/results/new/166298", // GPGC April 2
  //
  //   "https://practiscore.com/results/new/166447", // Gem City May
  //   "https://practiscore.com/results/new/168622", // Pardoe May
  //   "https://practiscore.com/results/new/167621", // LCSA May
  //   "https://practiscore.com/results/new/167183", // PMSC May
  //   "https://practiscore.com/results/new/167825", // Clairton May
  //   "https://practiscore.com/results/new/168462", // GPGC May
  //   "https://practiscore.com/results/new/169171", // Castlewood May
  //   "https://practiscore.com/results/new/168420", // EHPSA May
  //
  //   "https://practiscore.com/results/new/172505", // Pardoe June
  //   "https://practiscore.com/results/new/170223", // Gem City June
  //   "https://practiscore.com/results/new/170220", // PMSC June
  //   "https://practiscore.com/results/new/171664", // GPGC June
  //   "https://practiscore.com/results/new/171753", // Clairton June
  //   "https://practiscore.com/results/new/171470", // Castlewood June
  //   "https://practiscore.com/results/new/172303", // EHPSA June
  //
  //   "https://practiscore.com/results/new/174748", // Clairton July
  //   "https://practiscore.com/results/new/173327", // Gem City July
  //   "https://practiscore.com/results/new/175522", // Pardoe July
  //   "https://practiscore.com/results/new/173313", // PMSC July
  //   // "https://practiscore.com/results/new/173577", // Western PA section
  //   "https://practiscore.com/results/new/174574", // GPGC July
  //   "https://practiscore.com/results/new/175336", // Castlewood July
  //   "https://practiscore.com/results/new/175662", // EHPSA July
  // ];

  // var matchUrls = [ // Some locals
  //   "https://practiscore.com/results/new/165379", // 4/21 Delmarva
  //   "https://practiscore.com/results/new/168242", // 5/19 Mid-Atlantic
  //   "https://practiscore.com/results/new/170506", // 6/10 Buckeye Blast
  //   "https://practiscore.com/results/new/172099", // 6/24 MD State
  //   "https://practiscore.com/results/new/173577", // 7/08 WPA
  // ];

  var matchUrls = castlewoodMatchUrls;

  var matches = <PracticalMatch>[];
  for(String url in matchUrls) {
    var id = await processMatchUrl(url);
    if(id != null) {
      var match = await getPractiscoreMatchHeadless(id);
      if(match != null) {
        matches.add(match);
      }
    }
  }

  var openRankings = Rater(matches: matches, ratingSystem: MultiplayerPercentEloRater(), byStage: true, filters: FilterSet(empty: true)
    ..mode = FilterMode.or
    ..divisions = {
      Division.open: true,
    },
  );

  debugPrint("Member #,Shooter,Rating,Events");
  for(String memberNum in openRankings.knownShooters.keys) {
    var rating = openRankings.knownShooters[memberNum]!;

    debugPrint("$memberNum,${rating.shooter.getName(suffixes: false)},${rating.rating.round()},${rating.ratingEvents.length}");
  }

  var pccRankings = Rater(matches: matches, ratingSystem: MultiplayerPercentEloRater(), byStage: true, filters: FilterSet(empty: true)
    ..mode = FilterMode.or
    ..divisions = {
      Division.pcc: true,
    },
  );

  debugPrint("Member #,Shooter,Rating,Events");
  for(String memberNum in pccRankings.knownShooters.keys) {
    var rating = pccRankings.knownShooters[memberNum]!;

    debugPrint("$memberNum,${rating.shooter.getName(suffixes: false)},${rating.rating.round()},${rating.ratingEvents.length}");
  }

  var limitedRankings = Rater(matches: matches, ratingSystem: MultiplayerPercentEloRater(), byStage: true, filters: FilterSet(empty: true)
    ..mode = FilterMode.or
    ..divisions = {
      Division.limited: true,
    },
  );

  debugPrint("Member #,Shooter,Rating,Events");
  for(String memberNum in limitedRankings.knownShooters.keys) {
    var rating = limitedRankings.knownShooters[memberNum]!;

    debugPrint("$memberNum,${rating.shooter.getName(suffixes: false)},${rating.rating.round()},${rating.ratingEvents.length}");
  }

  var coRankings = Rater(matches: matches, ratingSystem: MultiplayerPercentEloRater(), byStage: true, filters: FilterSet(empty: true)
    ..mode = FilterMode.or
    ..divisions = {
      Division.carryOptics: true,
    },
  );

  debugPrint("Member #,Shooter,Rating,Events");
  for(String memberNum in coRankings.knownShooters.keys) {
    var rating = coRankings.knownShooters[memberNum]!;

    debugPrint("$memberNum,${rating.shooter.getName(suffixes: false)},${rating.rating.round()},${rating.ratingEvents.length}");
  }


  var locapRankings = Rater(matches: matches, ratingSystem: MultiplayerPercentEloRater(), byStage: true, filters: FilterSet(empty: true)
    ..mode = FilterMode.or
    ..divisions = {
      Division.limited10: true,
      Division.production: true,
      Division.singleStack: true,
      Division.revolver: true,
    },
  );

  debugPrint("Member #,Shooter,Rating,Events");
  for(String memberNum in locapRankings.knownShooters.keys) {
    var rating = locapRankings.knownShooters[memberNum]!;

    debugPrint("$memberNum,${rating.shooter.getName(suffixes: false)},${rating.rating.round()},${rating.ratingEvents.length}");
  }

  // var me = locapRankings.knownShooters["102675"]!;
  // for(var event in me.ratingEvents) {
  //   debugPrint("${me.shooter.getName(suffixes: false)} changed by ${event.ratingChange.round()} at ${event.eventName}");
  // }
}