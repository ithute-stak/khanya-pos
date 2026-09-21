import 'package:flutter/material.dart';
import 'package:khanya_pos/app/app.dart';
import 'package:khanya_pos/app/dependencies.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final dependencies = AppDependencies.create();
  runApp(KhanyaPosApp(dependencies: dependencies));
}
