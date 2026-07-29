import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app/tomo_read_app.dart';

export 'app/tomo_read_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();
  runApp(const TomoReadApp());
}
