import 'package:flutter/widgets.dart';

extension SetStateIfMounted<T extends StatefulWidget> on State<T> {
  void setStateIfMounted(VoidCallback fn) {
    if(mounted) {
      // ignore: invalid_use_of_protected_member
      setState(fn);
    }
  }
}
