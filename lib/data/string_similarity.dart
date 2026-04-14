/*
 *
 */

import 'package:shooting_sports_analyst/logger.dart';
import 'package:string_similarity/string_similarity.dart';

final _log = SSALogger("StringSimilarity");

/// Calculate the similarity between a query and a target string.
double calculateSimilarity(
  String queryLower, String targetLower,
  {bool printDebugInfo = false, bool matchAll = false}
) {
  var similarity = queryLower.similarityTo(targetLower);

  // Normalize similarity by the length of the event name.
  var similarityLengthFactor = targetLower.length / 20;
  similarity *= similarityLengthFactor;

  var similarityMultiplier = 1.0;
  var similarityBoost = 0.0;
  final similarityFactorPerWord = 0.5;
  final similarityBoostPerExactWord = 1;

  // A backward similarity factor of 1 will result in equal weight to forward
  // similarity, by the following example:
  // - query: "handgun"
  // - event name: "hand gun national championships"
  // - backward similarity for "hand" will be 4/7 * 1
  // - forward similarity for "hand" will be 3/4 * 1
  // - total similarity is 1
  // The reduction is because this is a fuzzier match to catch places where
  // a match name has a space and the query doesn't. (At present the DB query
  // doesn't have a way to return shorter-than-query-part matches, so this is not
  // helping if we search for "nationals" and want to get "national" matches as well.)
  final backwardSimilarityImpactFactor = 0.3;
  var eventNameWordsLower = targetLower.split(" ");
  var queryWordsLower = queryLower.split(" ");

  int exactWordMatches = 0;
  int partialWordMatches = 0;

  int backwardPartialMatches = 0;

  // Forward similarity: words in the query are matched against words in
  // the event name; query "national" will match the word "nationals"
  for(var word in queryWordsLower) {
    bool found = false;
    for(var eventNameWord in eventNameWordsLower) {
      if(eventNameWord.contains(word)) {
        found = true;
      }
      if(eventNameWord.startsWith(word)) {
        if(eventNameWord.length == word.length) {
          exactWordMatches += 1;
          similarityBoost += similarityBoostPerExactWord;
        }
        else {
          partialWordMatches += 1;
        }
        var similarityFactor = 1 + (word.length / eventNameWord.length) * similarityFactorPerWord;
        similarityMultiplier *= similarityFactor;
        // Each query word can only match an event word once.
        break;
      }
    }

    // If we require a match on all query terms and this word was not found in
    // any word in the event name, return no similarity.
    if(matchAll && !found) {
      return 0;
    }
  }

  // Backward similarity: words in the event name are matched against words in the query,
  // So that a query for "handgun" will match "hand gun" in the event name. Impact reduced.
  for(var eventNameWord in eventNameWordsLower) {
    for(var queryWord in queryWordsLower) {
      if(queryWord != eventNameWord && queryWord.contains(eventNameWord)) {
        backwardPartialMatches += 1;
        similarityMultiplier *= (1 + (eventNameWord.length / queryWord.length) * similarityFactorPerWord * backwardSimilarityImpactFactor);
      }
    }
  }

  if(printDebugInfo) {
    var debugString = "Similarity between $queryLower and $targetLower: ${(similarity + similarityBoost) * similarityMultiplier}";
    debugString += "\nExact word matches: $exactWordMatches";
    debugString += "\nPartial word matches: $partialWordMatches";
    debugString += "\nBackward partial matches: $backwardPartialMatches";
    debugString += "\nBase similarity: $similarity";
    debugString += "\nSimilarity boost: $similarityBoost";
    debugString += "\nSimilarity multiplier: $similarityMultiplier";

    _log.v(debugString);
  }
  return (similarity + similarityBoost) * similarityMultiplier;
}