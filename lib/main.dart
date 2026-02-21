import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/components/splashScreen.dart';
import 'package:flutter_application_1/db/pb.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final creds = await SharedPreferencesAsync();
  final token = await creds.getString('pb_token');
  final record = await creds.getString('pb_record');

  if (token != null && record != null) {
    final decoded = jsonDecode(record) as Map<String, dynamic>;
    pb.authStore.save(token, RecordModel.fromJson(decoded));
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: SplashScreenWidget(),
    );
  }
}
