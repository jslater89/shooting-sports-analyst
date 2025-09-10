/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/widgets.dart';

extension SetStateIfMounted<T extends StatefulWidget> on State<T> {
  void setStateIfMounted(VoidCallback fn) {
    if(mounted) {
      // ignore: invalid_use_of_protected_member
      setState(fn);
    }
  }
}
