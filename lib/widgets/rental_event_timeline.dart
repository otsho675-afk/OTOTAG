import 'package:flutter/material.dart';
import '../services/rental_service.dart';
import 'rental_market_style.dart';

class RentalEventHistory extends StatefulWidget {
  const RentalEventHistory(
      {super.key, required this.cursor, required this.load});
  final int cursor;
  final Future<Map<String, dynamic>> Function(int) load;
  @override
  State<RentalEventHistory> createState() => _RentalEventHistoryState();
}

class _RentalEventHistoryState extends State<RentalEventHistory> {
  late int? _cursor = widget.cursor;
  bool _loading = false;
  String? _error;
  final List<Map<String, dynamic>> _events = [];
  @override
  void initState() {
    super.initState();
    _more();
  }

  Future<void> _more() async {
    if (_loading || _cursor == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.load(_cursor!);
      if (mounted) {
        setState(() {
          _events.addAll([
            for (final row in data['events'] as List? ?? [])
              Map<String, dynamic>.from(row)
          ]);
          _cursor = data['next_cursor'] == null
              ? null
              : rentalId(data['next_cursor']);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
                title: const Text('Önceki hareketler'),
                trailing: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close))),
            Flexible(
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          RentalEventTimeline(events: _events),
                          if (_error != null)
                            Text(_error!,
                                style: const TextStyle(color: Colors.orange)),
                          if (_cursor != null)
                            OutlinedButton(
                                onPressed: _loading ? null : _more,
                                child: Text(_loading
                                    ? 'Yükleniyor…'
                                    : 'Daha önceki hareketler')),
                        ])))
          ])));
}

const rentalStages = {
  '': 'Tüm aşamalar',
  'pending': 'Pazarlık',
  'accepted': 'Rezerve',
  'completed': 'Tamamlandı',
  'cancelled': 'İptal edildi',
  'rejected': 'Teklif kapandı'
};
const rentalEventNames = {
  'listing_created': 'Araç ilana eklendi',
  'listing_updated': 'Araç bilgisi güncellendi',
  'listing_deleted': 'Araç ilandan kaldırıldı',
  'pickup_updated': 'Teslim konumu güncellendi',
  'offer_placed': 'Kiralama teklifi gönderildi',
  'counter_offer': 'Karşı teklif verildi',
  'offer_rejected': 'Teklif reddedildi / geri çekildi',
  'offer_closed': 'Bekleyen teklif kapandı',
  'reserved': 'Rezervasyon oluşturuldu',
  'completed': 'Araç iade edildi, kiralama tamamlandı',
  'admin_cancelled': 'Yönetici rezervasyonu iptal etti',
  'complaint_opened': 'Şikâyet açıldı',
  'review_added': 'Müşteri değerlendirmesi kaydedildi',
};

class RentalEventTimeline extends StatelessWidget {
  const RentalEventTimeline({super.key, required this.events});
  final List<Map<String, dynamic>> events;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Son hareketler',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        if (events.isEmpty)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                  'Bu kayıt için hareket geçmişi henüz yok. Eski işlemlerin mevcut durumu üstte gösterilir.',
                  style: TextStyle(color: rentalMuted, height: 1.5))),
        for (final event in events)
          Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: rentalField,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: rentalBorder)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        rentalEventNames[event['event_type']] ??
                            'Kiralama güncellendi',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(
                        '${{
                              'customer': 'Müşteri',
                              'rentacar': 'Firma',
                              'admin': 'Yönetici'
                            }[event['actor_role']] ?? 'Hesap'} #${event['actor_id']} • ${event['created_at']} UTC',
                        style: const TextStyle(
                            color: rentalMuted, fontSize: 11, height: 1.5)),
                    if (event['company_name'] != null)
                      Text('${event['company_name']} • ${event['city'] ?? ''}',
                          style: const TextStyle(
                              color: rentalMuted, fontSize: 12)),
                    if (event['details'] is Map) ...[
                      if (event['details']['amount'] != null)
                        Text('Toplam tutar: ${event['details']['amount']} ₺',
                            style: const TextStyle(color: Colors.greenAccent)),
                      if (event['details']['rating'] != null)
                        Text(
                            'Değerlendirme: ${rentalId(event['details']['rating'])} / 5',
                            style: const TextStyle(color: Colors.greenAccent)),
                      if (event['details']['subject'] != null)
                        Text('${event['details']['subject']}',
                            style: const TextStyle(color: rentalMuted)),
                      if (event['details']['reason'] != null)
                        Text('${event['details']['reason']}',
                            style: const TextStyle(color: rentalMuted)),
                      if (event['details']['vehicle'] != null)
                        Text('${event['details']['vehicle']}',
                            style: const TextStyle(color: rentalMuted)),
                      if (event['details']['daily_price'] != null)
                        Text(
                            'Günlük fiyat: ${event['details']['daily_price']} ₺',
                            style: const TextStyle(color: rentalMuted)),
                    ],
                  ])),
      ]);
}
