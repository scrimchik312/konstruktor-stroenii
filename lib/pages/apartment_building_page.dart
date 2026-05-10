import 'package:flutter/material.dart';

class ApartmentBuildingPage extends StatelessWidget {
  const ApartmentBuildingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Многоквартирный дом')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Раздел в разработке.\n\nПосле проработки частного дома вернёмся '
            'сюда и добавим расчёт многоквартирного дома.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
