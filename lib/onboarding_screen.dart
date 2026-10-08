import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants/app_constants.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.nextScreen});

  final Widget nextScreen;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  static const _items = [
    (
      icon: Icons.car_crash_rounded,
      title: 'Yolda kaldığında yalnız değilsin',
      text:
          'Konumuna yakın tamirci, çekici, lastikçi ve diğer hizmetleri tek ekrandan ara.'
    ),
    (
      icon: Icons.local_offer_rounded,
      title: 'Teklifleri karşılaştır',
      text:
          'Fiyatı, mesafeyi, tahmini varış süresini ve usta puanını karşılaştır.'
    ),
    (
      icon: Icons.verified_user_rounded,
      title: 'Aracını tek yerden yönet',
      text:
          'Muayene, sigorta, bakım, OBD, kiralama ve yol yardım özelliklerini OTO TAG ile takip et.'
    ),
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen_v2', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => widget.nextScreen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _finish,
              child: const Text('Geç',
                  style: TextStyle(color: Colors.white60)),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              onPageChanged: (value) => setState(() => _page = value),
              itemCount: _items.length,
              itemBuilder: (_, index) {
                final item = _items[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          color: AppConstants.primaryColor
                              .withValues(alpha: .12),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppConstants.primaryColor
                                  .withValues(alpha: .28)),
                        ),
                        child: Icon(item.icon,
                            color: AppConstants.primaryColor, size: 52),
                      ),
                      const SizedBox(height: 34),
                      Text(item.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              height: 1.1)),
                      const SizedBox(height: 14),
                      Text(item.text,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 15,
                              height: 1.55)),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
            child: Column(children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _items.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: index == _page ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: index == _page
                          ? AppConstants.primaryColor
                          : Colors.white24,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: () {
                    if (_page == _items.length - 1) {
                      _finish();
                    } else {
                      _controller.nextPage(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic);
                    }
                  },
                  child: Text(
                    _page == _items.length - 1 ? 'OTO TAG’a Başla' : 'Devam Et',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ]),
          )
        ]),
      ),
    );
  }
}
