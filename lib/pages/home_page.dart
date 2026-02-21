import 'package:flutter/material.dart';
import 'package:flutter_application_1/components/BadgeIcon.dart';
import 'package:flutter_application_1/db/pb.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final username = pb.authStore.record?.data["name"] ?? "Not Logged In";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ChatAppBar(),
      body: SafeArea(child: Center(child: Text('Name:- $username'))),
    );
  }

  AppBar ChatAppBar() {
    return AppBar(
      title: Text('Chat App'),
      centerTitle: false,
      leading: IconButton(
        style: IconButton.styleFrom(backgroundColor: Colors.blue[100]),
        onPressed: () => {},
        icon: Icon(Icons.menu, color: Colors.blue,),
      ),
      actions: <Widget>[
        Row(
          children: [
            IconButton(
              style: IconButton.styleFrom(backgroundColor: Colors.blue[100]),
              onPressed: () => {},
              icon: BadgeIcon(icon: Icon(Icons.notifications, color: Colors.blue,), count: 8),
            ),
            const SizedBox(width: 5),
            IconButton(
              style: IconButton.styleFrom(backgroundColor: Colors.blue[100]),
              onPressed: () => {},
              icon: Icon(Icons.account_circle, color: Colors.blue,),
            ),
          ],
        ),
      ],
    );
  }
}
