/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

extension ExtractSurname on String {
  ({String surname, bool isFinal}) extractSurname() {
    var nameParts = this.split(" ");
    String? lastName;
    bool isFinal = true;
    if(nameParts.length > 1) {
      lastName = nameParts.last;

      /// Handle some common non-last-name suffixes
      if(nameParts.length > 2) {
        isFinal = false;
        final lowercaseLastName = lastName.toLowerCase().replaceAll(RegExp(r"[^a-z]"), "");
        if(lowercaseLastName == "jr" || lowercaseLastName == "sr" || lowercaseLastName == "ii" || lowercaseLastName == "iii") {
          lastName = nameParts[nameParts.length - 2];
        }
      }
    }
    else {
      lastName = this;
    }
    return (surname: lastName, isFinal: isFinal);
  }
}

extension HasCommonNickname on String {
  /// Check if there are likely variants of this name that may require manual checking on name matching.
  bool get hasCommonNickname {
    var nameParts = this.split(" ");
    if(nameParts.isEmpty) return false;

    // Check for common surname suffixes
    final lastName = nameParts.last.toLowerCase();
    if(lastName == "jr" || lastName == "sr" || lastName == "ii" || lastName == "iii") return true;

    // Check for common first names with nicknames.
    final firstName = nameParts.first.toLowerCase();
    if(firstName.startsWith("michael") || firstName.startsWith("mike")) return true;
    if(firstName.startsWith("james") || firstName.startsWith("jim")) return true;
    if(firstName.startsWith("will") || firstName.startsWith("bill")) return true;
    if(firstName.startsWith("richard") || firstName.startsWith("rick")) return true;
    if(firstName.startsWith("david") || firstName.startsWith("dave")) return true;
    if(firstName.startsWith("thomas") || firstName.startsWith("tom")) return true;
    if(firstName.startsWith("john") || firstName.startsWith("jon")) return true;
    if(firstName.startsWith("robert") || firstName.startsWith("bob")) return true;
    if(firstName.startsWith("charles") || firstName.startsWith("charlie") || firstName.startsWith("chuck")) return true;
    if(firstName.startsWith("anthony") || firstName.startsWith("tony")) return true;
    if(firstName.startsWith("dan")) return true;
    if(firstName.startsWith("matt")) return true;
    if(firstName.startsWith("pete")) return true;
    if(firstName.startsWith("andrew") || firstName.startsWith("andy") || firstName.startsWith("drew")) return true;
    if(firstName.startsWith("joseph") || firstName.startsWith("joe")) return true;
    if(firstName.startsWith("ron")) return true;
    if(firstName.startsWith("don")) return true;
    if(firstName.startsWith("jeff") || firstName.startsWith("geoff")) return true;
    if(firstName.startsWith("steve") || firstName.startsWith("steph")) return true;
    if(firstName.startsWith("greg")) return true;
    if(firstName.startsWith("zac")) return true;
    if(firstName.startsWith("josh")) return true;
    if(firstName.startsWith("chris")) return true;
    if(firstName.startsWith("brad")) return true;


    return false;
  }
}