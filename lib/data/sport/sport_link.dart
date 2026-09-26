/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'package:shooting_sports_analyst/data/sport/builtins/registry.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/filter_set.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

/// A sport link describes a directed pair of sports that are compatible for scoring/rating purposes,
/// containing information on mapping one to the other.
///
/// For example, IPSC and USPSA are the same underlying sport, with differently-named divisions.
/// Same deal with World Revolver Championship and ICORE.
///
/// Sport links are directed: sourceSportName feeds into targetSportName but not vice versa,
/// assuming that no inverse link has been created.
class SportLink {
  final String targetSportName;
  final String sourceSportName;

  /// Whether scores from the source sport can be ingested into rating projects for
  /// the target sport.
  final bool canIngest;

  /// Whether ratings from the target sport can be used for predictions for the source
  /// sport.
  final bool canPredict;

  Sport get sourceSport => SportRegistry().lookup(sourceSportName)!;
  Sport get targetSport => SportRegistry().lookup(targetSportName)!;

  List<DivisionLink> divisionLinks = [];

  void attachDivisionLink(DivisionLink link) {
    link.parent = this;

    try {
      link.sourceDivisions;
    } catch (e) {
      throw ArgumentError("Invalid division link: one or more of ${link.sourceDivisionNames} does not exist in the source sport");
    }

    try {
      link.targetDivision;
    } catch (e) {
      throw ArgumentError("Invalid division link: ${link.targetDivisionName} does not exist in the target sport");
    }

    divisionLinks.add(link);

    for (var sourceDivision in link.sourceDivisions) {
      _sourceToTargetDivisions[sourceDivision] = link.targetDivision;
    }
    _targetToSourceDivisions.putIfAbsent(link.targetDivision, () => []).addAll(link.sourceDivisions);
  }

  /// Return the target division that is compatible with the given source division, if any. When updating
  /// ratings, matches from the source division should use the returned target division, or be ignored.
  Division? targetCompatibleDivision(Division sourceDivision) {
    return _sourceToTargetDivisions[sourceDivision];
  }

  /// Return the target division that is compatible with the given source division name, if any.
  Division? targetCompatibleDivisionForName(String sourceDivisionName) {
    final sourceDivision = sourceSport.divisions.lookupByName(sourceDivisionName, fallback: false);
    if(sourceDivision == null) return null;
    return targetCompatibleDivision(sourceDivision);
  }

  /// Return the source divisions compatible with the given target division name, if any.
  List<Division> sourceCompatibleDivisionsForName(String targetDivisionName) {
    final targetDivision = targetSport.divisions.lookupByName(targetDivisionName, fallback: false);
    if(targetDivision == null) return [];
    return sourceCompatibleDivisions(targetDivision);
  }

  /// Return the source divisions compatible with the given target division, if any. When viewing match
  /// results in the source sport from a context that uses target divisions or groups.
  ///
  /// This will almost always return a one-element list, but occasional cases
  /// like IPSC PCC Irons and IPSC PCC Optics <-> USPSA PCC require a multi-element list.
  List<Division> sourceCompatibleDivisions(Division targetDivision) {
    return _targetToSourceDivisions[targetDivision] ?? [];
  }

  /// Given a list of divisions in the target sport, return a list that contains both the original
  /// divisions and any source divisions that correspond to those divisions.
  ///
  /// This is the reverse-direction operation: given a list of target divisions, find the corresponding
  /// source divisions.
  List<Division> withSourceEquivalents(List<Division> targetDivisions) {
    final outDivisions = [...targetDivisions];
    for (var targetDivision in targetDivisions) {
      outDivisions.addAll(sourceCompatibleDivisions(targetDivision));
    }
    return outDivisions;
  }

  /// Create a filter set that includes all divisions in the source sport and their equivalents in the target sport.
  FilterSet sourceCompatibleFilters() {
    return sourceCompatibleFiltersFor(sourceSport.divisions.values.toList());
  }

  /// Create a filter set that includes all divisions in the target sport and their equivalents in the source sport.
  FilterSet targetCompatibleFilters() {
    return targetCompatibleFiltersFor(targetSport.divisions.values.toList());
  }

  /// Create a filter set that includes all [targetDivisions] and their equivalents in the source sport.
  FilterSet targetCompatibleFiltersFor(List<Division> targetDivisions) {
    final outFilters = FilterSet(targetSport, mode: FilterMode.or, empty: true);
    outFilters.reentries = true;
    outFilters.scoreDQs = true;
    final combinedDivisions = withSourceEquivalents(targetDivisions);
    outFilters.divisions = FilterSet.divisionListToMap(targetSport, combinedDivisions, validate: false);
    return outFilters;
  }

  /// Create a filter set that includes all [sourceDivisions] and their equivalents in the target sport.
  FilterSet sourceCompatibleFiltersFor(List<Division> sourceDivisions) {
    final outFilters = FilterSet(sourceSport, mode: FilterMode.or, empty: true);
    outFilters.reentries = true;
    outFilters.scoreDQs = true;
    final combinedDivisions = withTargetEquivalents(sourceDivisions);
    outFilters.divisions = FilterSet.divisionListToMap(sourceSport, combinedDivisions, validate: false);
    return outFilters;
  }

  /// Given a list of divisions in the source sport, return a list that contains both the original
  /// divisions and any target divisions that correspond to those divisions.
  ///
  /// This is the forward-direction operation: given a list of source divisions, find the corresponding
  /// target divisions.
  List<Division> withTargetEquivalents(List<Division> sourceDivisions) {
    final outDivisions = [...sourceDivisions];
    for (var sourceDivision in sourceDivisions) {
      final targetDivision = targetCompatibleDivision(sourceDivision);
      if(targetDivision != null) {
        outDivisions.add(targetDivision);
      }
    }
    return outDivisions;
  }

  Map<Division, Division> _sourceToTargetDivisions = {};
  Map<Division, List<Division>> _targetToSourceDivisions = {};

  SportLink({
    required Sport targetSport,
    required Sport sourceSport,
    required this.canIngest,
    required this.canPredict,
    List<DivisionLink> divisionLinks = const [],
  }) : targetSportName = targetSport.name, sourceSportName = sourceSport.name {
    for (var divisionLink in divisionLinks) {
      attachDivisionLink(divisionLink);
    }
  }
}

class DivisionLink {
  late final SportLink parent;
  final List<String> sourceDivisionNames;
  final String targetDivisionName;

  List<Division> get sourceDivisions => sourceDivisionNames.map((name) => parent.sourceSport.divisions.lookupByName(name, fallback: false)!).toList();
  Division get targetDivision => parent.targetSport.divisions.lookupByName(targetDivisionName, fallback: false)!;

  DivisionLink({
    required List<Division> sourceDivisions,
    required Division targetDivision,
  }) : sourceDivisionNames = sourceDivisions.map((division) => division.name).toList(), targetDivisionName = targetDivision.name;
}