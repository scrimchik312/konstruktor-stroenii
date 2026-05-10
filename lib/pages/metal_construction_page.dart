import 'package:flutter/material.dart';

class MetalConstructionPage extends StatelessWidget {
  const MetalConstructionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Металлические конструкции')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Раздел в разработке.\n\nЗдесь появится расчёт металлических '
            'конструкций после готовности модуля частного дома.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
