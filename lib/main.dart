import 'package:flutter/widgets.dart';

import 'app/tomo_read_app.dart';

export 'app/tomo_read_app.dart';

void main(List<String> arguments) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(TomoReadApp(initialImportArguments: arguments));
}
