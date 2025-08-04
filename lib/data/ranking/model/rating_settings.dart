/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

abstract class RaterSettings {
  void loadFromJson(Map<String, dynamic> json);
  void encodeToJson(Map<String, dynamic> json);
}
