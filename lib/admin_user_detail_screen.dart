import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'core/constants/app_constants.dart';

/// Kullanıcı, araçları ve etkinliklerinin tek noktadan yönetildiği responsive konsol.
class AdminUserDetailScreen extends StatefulWidget {
  const AdminUserDetailScreen({super.key, required this.userId, this.onChanged});
  final int userId;
  final VoidCallback? onChanged;

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  Map<String, dynamic> _details = {};
  bool _busy = false;
  String? _error;

  Map<String, dynamic> get _user =>
      Map<String, dynamic>.from(_details['user'] is Map ? _details['user'] as Map : {});
  List<Map<String, dynamic>> _rows(String key) => (_details[key] is List
          ? _details[key] as List : const [])
      .whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  String _str(dynamic v) => v == null || v.toString().isEmpty ? '—' : v.toString();
  bool _flag(dynamic v) => v == 1 || v == '1' || v == true;
  String _date(dynamic raw) {
    if (raw == null || raw.toString().trim().isEmpty) return 'Henüz kayıt yok';
    final dt = DateTime.tryParse(raw.toString());
    if (dt == null) return raw.toString();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(dt.day)}.${pad(dt.month)}.${dt.year} ${pad(dt.hour)}:${pad(dt.minute)}';
  }
  String _role(String role) => switch (role) {
    'customer' => 'Müşteri', 'provider' => 'Usta', 'rentacar' => 'Rent a Car',
    _ => role,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _busy = true; _error = null; });
    try {
      final uri = Uri.parse(AppConstants.baseUrl).replace(queryParameters: {
        'action': 'admin_get_user_detail', 'user_id': '${widget.userId}',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 18));
      final data = jsonDecode(response.body);
      if (response.statusCode != 200 || data is! Map || data['status'] != 'success') {
        throw Exception(data is Map ? _str(data['message']) : 'Veri alınamadı');
      }
      if (mounted) setState(() => _details = Map<String, dynamic>.from(data));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _post(String action, Map<String, String> fields) async {
    try {
      final response = await http.post(
        Uri.parse(AppConstants.baseUrl).replace(queryParameters: {'action': action}),
        body: {'user_id': '${widget.userId}', ...fields},
      ).timeout(const Duration(seconds: 18));
      final data = jsonDecode(response.body);
      if (data is! Map || data['status'] != 'success' || response.statusCode >= 300) {
        throw Exception(data is Map ? _str(data['message']) : 'İşlem başarısız');
      }
      widget.onChanged?.call();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Değişiklik kaydedildi.')));
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
      return false;
    }
  }

  Future<bool> _confirm(String title, String description) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Onayla')),
        ],
      ),
    ) ?? false;

  void _editUser() {
    final u = _user;
    final fields = {
      for (final key in ['name','phone','email','city','service_category','iban'])
        key: TextEditingController(text: u[key]?.toString() ?? ''),
    };
    String status = ['active','pending','banned','rejected'].contains(u['status'])
        ? u['status'].toString() : 'pending';
    bool premium = _flag(u['is_premium']);
    bool suspended = _flag(u['is_suspended']);
    showDialog<void>(context: context, builder: (dialogContext) =>
      StatefulBuilder(builder: (ctx, update) => AlertDialog(
        title: const Text('Üyeyi düzenle'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final entry in fields.entries) Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: entry.value,
                decoration: InputDecoration(
                  labelText: const {
                    'name':'Ad soyad','phone':'Telefon','email':'E-posta',
                    'city':'Şehir','service_category':'Hizmet türü','iban':'IBAN'
                  }[entry.key],
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            DropdownButtonFormField<String>(
              initialValue: status,
              decoration: const InputDecoration(labelText: 'Hesap durumu',border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value:'active', child:Text('Aktif')),
                DropdownMenuItem(value:'pending', child:Text('Onay bekliyor')),
                DropdownMenuItem(value:'banned', child:Text('Engelli')),
                DropdownMenuItem(value:'rejected', child:Text('Reddedildi')),
              ],
              onChanged: (v) { if (v != null) update(() => status = v); },
            ),
            SwitchListTile(title: const Text('Premium'), value: premium, onChanged:(v) => update(() => premium = v)),
            SwitchListTile(title: const Text('Askıya alındı'),value:suspended,onChanged:(v) => update(() => suspended = v)),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton.icon(onPressed: () async {
            final values = {for (final f in fields.entries) f.key: f.value.text.trim()};
            values['status'] = status;
            values['is_premium'] = premium ? '1' : '0';
            values['is_suspended'] = suspended ? '1' : '0';
            Navigator.pop(ctx);
            await _post('admin_update_user', values);
            for (final c in fields.values) { c.dispose(); }
          }, icon: const Icon(Icons.save_outlined), label: const Text('Kaydet')),
        ],
      )));
  }

  void _editVehicle([Map<String, dynamic>? vehicle]) {
    final existing = vehicle != null;
    final keys = [
      'plate','brand_model','engine_type','model_year','current_km','maintenance_km',
      'insurance_date','inspection_date','mtv_date',
    ];
    final labels = {
      'plate':'Plaka','brand_model':'Marka / model','engine_type':'Yakıt',
      'model_year':'Model yılı','current_km':'Güncel kilometre',
      'maintenance_km':'Bakım kilometresi','insurance_date':'Sigorta (YYYY-AA-GG)',
      'inspection_date':'Muayene (YYYY-AA-GG)','mtv_date':'MTV (YYYY-AA-GG)',
    };
    final controllers = {
      for(final k in keys) k: TextEditingController(text: vehicle?[k]?.toString() ?? '')
    };
    showDialog<void>(context: context,builder:(ctx) => AlertDialog(
      title: Text(existing ? 'Aracı düzenle' : 'Araç ekle'),
      content:SizedBox(width:500,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        for(final key in (existing ? keys : keys.take(2))) Padding(
          padding: const EdgeInsets.only(bottom:10),
          child: TextField(
            controller: controllers[key],
            keyboardType: ['current_km','maintenance_km','model_year'].contains(key)
                ? TextInputType.number : TextInputType.text,
            decoration: InputDecoration(labelText:labels[key],border:const OutlineInputBorder()),
          ),
        )
      ]))),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Vazgeç')),
        FilledButton(onPressed:() async {
          final values = {for(final key in (existing ? keys : keys.take(2)))
              key: controllers[key]!.text.trim()};
          if (existing) values['vehicle_id'] = vehicle['id'].toString();
          Navigator.pop(ctx);
          await _post(existing ? 'admin_update_vehicle' : 'admin_add_vehicle', values);
          for (final c in controllers.values) { c.dispose(); }
        },child:const Text('Kaydet')),
      ],
    ));
  }

  Widget _sectionTitle(String title, IconData icon) => Padding(
    padding: const EdgeInsets.only(top:18,bottom:10),
    child:Row(children:[Icon(icon,size:19),const SizedBox(width:8),
      Text(title,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w800))]),
  );
  Widget _info(String label, dynamic value) => Padding(
    padding:const EdgeInsets.symmetric(vertical:7),
    child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
      SizedBox(width:135,child:Text(label,style:const TextStyle(color:Colors.grey,fontSize:12))),
      Expanded(child:Text(_str(value),style:const TextStyle(fontWeight:FontWeight.w600))),
    ]),
  );
  Widget _panel(Widget child) => Card(
    margin:const EdgeInsets.only(bottom:12),
    clipBehavior:Clip.antiAlias,
    child:Padding(padding:const EdgeInsets.all(18),child:child),
  );

  Widget _profileTab() {
    final u = _user;
    return LayoutBuilder(builder:(ctx, size) {
      final base = _panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        _sectionTitle('Hesap bilgileri',Icons.account_circle_outlined),
        _info('Üye numarası',u['id']),_info('Ad soyad',u['name']),
        _info('Telefon',u['phone']),_info('E-posta',u['email']),
        _info('Şehir',u['city']),_info('Üye tipi',_role(_str(u['user_type']))),
        _info('Hizmet alanı',u['service_category']),_info('IBAN',u['iban']),
        _info('Durum',u['status']),_info('Premium',_flag(u['is_premium']) ? 'Evet':'Hayır'),
        _info('Askıda',_flag(u['is_suspended']) ? 'Evet':'Hayır'),
        _info('Kayıt',_date(u['created_at'])),
        const SizedBox(height:12),
        FilledButton.icon(onPressed:_editUser, icon:const Icon(Icons.edit_outlined),label:const Text('Bilgileri düzenle')),
      ]));
      final activity = _panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        _sectionTitle('Oturum ve kullanım',Icons.schedule_outlined),
        _info('Son giriş',_date(u['last_login_at'])),
        _info('Son etkinlik',_date(u['last_seen_at'])),
        _info('Giriş sayısı',u['login_count'] ?? '0'),
        _info('Kayıtlı araç',_rows('vehicles').length),
        _info('İşlem sayısı',_rows('jobs').length),
        const SizedBox(height:8),
        const Text('Giriş ve hareket bilgileri kayıt sistemi etkinleştirildikten sonra oluşur. Eski oturumlar geriye dönük hesaplanmaz.',style:TextStyle(color:Colors.grey,fontSize:12)),
        const SizedBox(height:12),
        OutlinedButton.icon(onPressed:_load,icon:const Icon(Icons.refresh),label:const Text('Bilgileri yenile')),
      ]));
      if (size.maxWidth >= 900) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: base),
            const SizedBox(width: 14),
            Expanded(flex: 2, child: activity),
          ]),
        );
      }
      return ListView(padding:const EdgeInsets.all(14),children:[base,activity]);
    });
  }

  Widget _vehicleTab() {
    final fleet = _rows('vehicles');
    final records = _rows('vehicle_records');
    return ListView(padding:const EdgeInsets.all(14),children:[
      Wrap(alignment:WrapAlignment.spaceBetween,crossAxisAlignment:WrapCrossAlignment.center,spacing:14,runSpacing:8,children:[
        Text('Kullanıcının araçları (${fleet.length})',style:const TextStyle(fontSize:18,fontWeight:FontWeight.w800)),
        if (_user['user_type']=='customer') FilledButton.icon(onPressed:()=>_editVehicle(),icon:const Icon(Icons.add),label:const Text('Araç ekle')),
      ]),
      const SizedBox(height:14),
      if(fleet.isEmpty) const ListTile(leading:Icon(Icons.directions_car_outlined),title:Text('Kayıtlı araç bulunamadı')),
      for(final v in fleet) _panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Wrap(alignment:WrapAlignment.spaceBetween,crossAxisAlignment:WrapCrossAlignment.center,spacing:8,runSpacing:8,children:[
          Text('${_str(v['plate'])} • ${_str(v['brand_model'])}',
            style:const TextStyle(fontWeight:FontWeight.w800,fontSize:16)),
          Wrap(spacing:8,children:[
            OutlinedButton.icon(onPressed:()=>_editVehicle(v),icon:const Icon(Icons.edit_outlined,size:17),label:const Text('Düzenle')),
            OutlinedButton.icon(onPressed:() async {
              if(!await _confirm('Araç silinsin mi?','Araç ve bakım kayıtları silinecek. Bu işlem geri alınamaz.')) return;
              await _post('admin_delete_vehicle',{'vehicle_id':v['id'].toString()});
            },icon:const Icon(Icons.delete_outline,size:17),label:const Text('Sil')),
          ]),
        ]),
        _info('Model yılı',v['model_year']),_info('Yakıt',v['engine_type']),
        _info('Kilometre',v['current_km']),_info('Bakım hedefi',v['maintenance_km']),
        _info('Muayene',v['inspection_date']),_info('Sigorta',v['insurance_date']),
        _info('MTV',v['mtv_date']),
        if(records.any((r)=>'${r['vehicle_id']}'=='${v['id']}')) ...[
          const Divider(),
          const Text('Bakım / araç kayıtları',style:TextStyle(fontWeight:FontWeight.bold)),
          for(final r in records.where((r)=>'${r['vehicle_id']}'=='${v['id']}'))
            ListTile(
              contentPadding:EdgeInsets.zero,
              title:Text('${_str(r['record_type'])} • ${_str(r['description'])}'),
              subtitle:Text('${_date(r['created_at'])}   •   Tutar: ${_str(r['cost'])}'),
              trailing:IconButton(tooltip:'Kaydı sil',icon:const Icon(Icons.delete_outline),onPressed:() async {
                if (!await _confirm('Kayıt silinsin mi?','Araç bakım kaydı silinecek.')) return;
                await _post('admin_delete_vehicle_record',{'vehicle_id':'${v['id']}','record_id':'${r['id']}'});
              }),
            ),
        ],
      ])),
    ]);
  }

  Widget _activityTab() {
    final events = <Map<String,dynamic>>[
      for(final e in _rows('activity')) {...e,'_kind':'Sistem / yetkili'},
      for(final e in _rows('telemetry')) {...e,'_kind':'Uygulama telemetrisi'},
    ]..sort((a,b)=>_str(b['created_at']).compareTo(_str(a['created_at'])));
    return ListView(padding:const EdgeInsets.all(14),children:[
      _panel(const Text('Bu ekran son kaydedilen oturum olaylarını, işlem isteklerini ve uygulama telemetrisini gösterir. Telemetri, işlemin başarıyla tamamlandığını tek başına kanıtlamaz.',style:TextStyle(fontSize:12))),
      if(events.isEmpty)const ListTile(title:Text('Henüz hareket kaydı bulunamadı')),
      for(final e in events) Card(child:ListTile(
        leading:Icon(e['_kind']=='Uygulama telemetrisi' ? Icons.touch_app_outlined : Icons.history),
        title:Text(_str(e['event_name'])),
        subtitle:Text('${_str(e['_kind'])}  ·  ${_str(e['screen_name']) == '—' ? '' : '${e['screen_name']} · '}${_date(e['created_at'])}'),
        isThreeLine:false,
      )),
    ]);
  }

  Widget _jobsTab() {
    final jobs = _rows('jobs');
    return ListView(padding:const EdgeInsets.all(14),children:[
      _sectionTitle('İş ve servis geçmişi (${jobs.length})',Icons.receipt_long_outlined),
      if(jobs.isEmpty) const ListTile(title:Text('Servis kaydı bulunamadı')),
      for(final j in jobs) Card(child:ListTile(
        title:Text('#${_str(j['id'])} • ${_str(j['service_type'])}',style:const TextStyle(fontWeight:FontWeight.bold)),
        subtitle:Text('${_date(j['created_at'])} · ${_str(j['status'])} · ${_str(j['agreed_price'])} TL'),
        trailing:IconButton(tooltip:'İş kaydını sil',icon:const Icon(Icons.delete_outline),onPressed:() async {
          if (!await _confirm('İş silinsin mi?','İşlem ve bağlı kayıtlar silinebilir. Kiralama işlemleri özel iptal akışından yönetilir.')) return;
          await _post('admin_delete_job',{'job_id':j['id'].toString()});
        }),
      )),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final u = _user;
    return DefaultTabController(length:4,child:Scaffold(
      appBar:AppBar(title:const Text('Üye yönetimi'),actions:[
        IconButton(onPressed:_busy?null:_load,icon:const Icon(Icons.refresh),tooltip:'Yenile'),
        IconButton(onPressed:u.isEmpty?null:() async {
          if(!await _confirm('Üye kalıcı silinsin mi?','Bu kullanıcı ve ilişkili verileri silinecek. Geri alınamaz.')) return;
          final done = await _post('admin_delete_user',{});
          if(done && context.mounted) Navigator.pop(context);
        },icon:const Icon(Icons.person_remove_outlined),tooltip:'Kullanıcıyı sil'),
      ]),
      body:_busy && u.isEmpty
        ?const Center(child:CircularProgressIndicator())
        : _error!=null && u.isEmpty
          ? Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
              Text(_error!,textAlign:TextAlign.center),const SizedBox(height:12),
              FilledButton(onPressed:_load,child:const Text('Tekrar dene')),
            ])))
          :Column(children:[
            Container(width:double.infinity,padding:const EdgeInsets.fromLTRB(20,16,20,14),child:Wrap(
              crossAxisAlignment:WrapCrossAlignment.center,spacing:16,runSpacing:12,children:[
                CircleAvatar(radius:25,child:Text(_str(u['name']).substring(0,1).toUpperCase())),
                Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text(_str(u['name']),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:20)),
                  Text('${_role(_str(u['user_type']))} • #${widget.userId} • ${_str(u['status'])}',
                    style:const TextStyle(fontSize:12,color:Colors.grey)),
                ]),
              ],
            )),
            const TabBar(isScrollable:true,tabs:[
              Tab(icon:Icon(Icons.person_outline),text:'Profil ve giriş'),
              Tab(icon:Icon(Icons.directions_car_outlined),text:'Araçlar'),
              Tab(icon:Icon(Icons.timeline_outlined),text:'Hareketler'),
              Tab(icon:Icon(Icons.work_history_outlined),text:'İşlemler'),
            ]),
            if(_busy)const LinearProgressIndicator(minHeight:2),
            Expanded(child:TabBarView(children:[
              _profileTab(),_vehicleTab(),_activityTab(),_jobsTab(),
            ])),
          ]),
    ));
  }
}
