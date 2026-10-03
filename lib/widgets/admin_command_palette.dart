import 'package:flutter/material.dart';

String adminSearchText(String value) => value
    .replaceAll('İ', 'i')
    .replaceAll('I', 'i')
    .toLowerCase()
    .replaceAll('ı', 'i')
    .replaceAll('ş', 's')
    .replaceAll('ğ', 'g')
    .replaceAll('ü', 'u')
    .replaceAll('ö', 'o')
    .replaceAll('ç', 'c')
    .trim();

class AdminCommand {
  const AdminCommand(this.id, this.title, this.subtitle, this.icon,
      {this.keywords = ''});
  final String id, title, subtitle, keywords;
  final IconData icon;
  bool matches(String query) {
    final terms = adminSearchText(query).split(RegExp(r'\s+'));
    final text = adminSearchText('$title $subtitle $keywords');
    return terms.every(text.contains);
  }
}

class AdminCommandPalette extends StatefulWidget {
  const AdminCommandPalette({super.key, required this.commands});
  final List<AdminCommand> commands;
  @override
  State<AdminCommandPalette> createState() => _AdminCommandPaletteState();
}

class _AdminCommandPaletteState extends State<AdminCommandPalette> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final results = widget.commands.where((c) => c.matches(_query)).toList();
    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: 580, maxHeight: MediaQuery.sizeOf(context).height * .8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
            child: Row(children: [
              const Expanded(
                  child: Text('Yönetimde ara',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700))),
              IconButton(
                  tooltip: 'Kapat',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              onSubmitted: (_) {
                if (results.isNotEmpty) {
                  Navigator.pop(context, results.first.id);
                }
              },
              decoration: const InputDecoration(
                  hintText: 'Bölüm veya araç ara…',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder()),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: results.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                        'Eşleşen bölüm bulunamadı. Başka bir kelime deneyin.'))
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final command = results[index];
                      return ListTile(
                          leading: Icon(command.icon),
                          title: Text(command.title),
                          subtitle: Text(command.subtitle),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.pop(context, command.id));
                    }),
          ),
        ]),
      ),
    );
  }
}
