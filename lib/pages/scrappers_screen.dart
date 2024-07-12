import 'package:flutter/material.dart';

class ScrappersScreen extends StatelessWidget {
  const ScrappersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scrappers'),
      ),
      body: const Center(
        child: Text(
          'Scrappers',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}