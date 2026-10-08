import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/constants/app_constants.dart';
import 'main.dart' show RoleSelectionScreen;

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  static const _pages = [
    (
      Icons.car_crash_outlined,
      'Yolda kaldın mı?',
      'Konumunu paylaş, ihtiyacını seç ve yakınındaki hizmet sağlayıcıları tara.'
    ),
    (
      Icons.compare_arrows_rounded,
      'Teklifleri karşılaştır',
      'Fiyatı, mesafeyi, tahmini varış süresini ve usta puanını tek ekranda gör.'
    ),
    (
      Icons.verified_user_outlined,
      'Seç ve takip et',
      'Doğrulanmış sağlayıcıyı seç, canlı konumu takip et ve işlemi güvenle tamamla.'
    ),
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ototag_onboarding_seen', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppConstants.bgColor,
    body: SafeArea(
      child: Column(children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: _finish, child: const Text('Geç')),
        ),
        Expanded(
          child: PageView.builder(
            controller: _controller,
            itemCount: _pages.length,
            onPageChanged: (value) => setState(() => _index = value),
            itemBuilder: (_, i) {
              final page = _pages[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 126,
                      height: 126,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppConstants.primaryColor.withValues(alpha: .12),
                        border: Border.all(color: AppConstants.primaryColor.withValues(alpha: .35)),
                      ),
                      child: Icon(page.$1, size: 56, color: AppConstants.primaryColor),
                    ),
                    const SizedBox(height: 34),
                    Text(page.$2,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 14),
                    Text(page.$3,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white60, height: 1.55, fontSize: 15)),
                  ],
                ),
              );
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _pages.length,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == _index ? 26 : 8,
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: i == _index ? AppConstants.primaryColor : Colors.white24,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 26),
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: () {
                if (_index == _pages.length - 1) {
                  _finish();
                } else {
                  _controller.nextPage(duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
                }
              },
              child: Text(_index == _pages.length - 1 ? 'OTO TAG’a Başla' : 'Devam Et'),
            ),
          ),
        )
      ]),
    ),
  );
}
