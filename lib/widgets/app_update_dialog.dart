import 'package:flutter/material.dart';
import '../services/app_update_service.dart';

class AppUpdateDialog extends StatelessWidget {
  const AppUpdateDialog(
      {super.key,
      required this.release,
      required this.onUpdate,
      this.onLater,
      this.opening = false,
      this.error});
  final AppRelease release;
  final VoidCallback onUpdate;
  final VoidCallback? onLater;
  final bool opening;
  final String? error;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !release.requiredUpdate,
        child: AlertDialog(
          scrollable: true,
          icon: const Icon(Icons.system_update_rounded, size: 36),
          title: Text(release.title, textAlign: TextAlign.center),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${release.platform == 'ios' ? 'iPhone' : 'Android'} • Sürüm ${release.displayVersion}',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 12),
                Text(release.message),
                const SizedBox(height: 12),
                Text(
                    release.requiredUpdate
                        ? 'Devam etmek için uygulamayı güncelleyin.'
                        : 'Güncellemeyi şimdi yapabilir veya daha sonra hatırlatmamızı seçebilirsiniz.',
                    style: Theme.of(context).textTheme.bodySmall),
                if (error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
              ]),
          actions: [
            if (!release.requiredUpdate && onLater != null)
              TextButton(
                  onPressed: opening ? null : onLater,
                  child: const Text('Daha sonra')),
            FilledButton.icon(
                onPressed: opening ? null : onUpdate,
                icon: Icon(opening
                    ? Icons.hourglass_top_rounded
                    : Icons.open_in_new_rounded),
                label: Text(opening ? 'Mağaza açılıyor…' : 'Güncelle')),
          ],
        ),
      );
}
