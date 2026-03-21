import 'package:flutter/material.dart';
import 'services/database_service.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseService.init();
  runApp(const OffMusicApp());
}
