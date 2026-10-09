// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'admin_settings_panel.dart';

/// Unified, adaptive member directory. All mutations use existing callbacks.
class AdminMembersPanel extends StatelessWidget {
  const AdminMembersPanel({
    super.key, required this.users, required this.total, this.activityFetchedAt,
    this.lightMode = false,
    required this.searchController,
    required this.query, required this.filter, required this.sort, required this.bulk,
    required this.selected, required this.hiddenCount, required this.onSearch,
    required this.onFilter, required this.onSort, required this.onToggleBulk,
    required this.onToggleUser, required this.onSelectAll, required this.onHide,
    required this.onDeleteSelected, required this.onRestore, required this.onOpen,
    required this.onNotify, required this.onDocs, required this.onPunish,
    required this.onReviews, required this.onDelete,
  });
  final List<Map<String,dynamic>> users;
  final int total, hiddenCount;
  final DateTime? activityFetchedAt;
  final bool lightMode;
  final TextEditingController searchController;
  final String query, filter, sort;
  final bool bulk;
  final Set<int> selected;
  final ValueChanged<String> onSearch, onFilter, onSort;
  final VoidCallback onToggleBulk, onSelectAll, onHide, onDeleteSelected, onRestore;
  final ValueChanged<int> onToggleUser;
  final ValueChanged<Map<String,dynamic>> onOpen, onNotify, onDocs, onPunish, onReviews, onDelete;

  Color get background => lightMode ? Color(0xFFF6F8F6) : Color(0xFF0B120F);
  Color get surface => lightMode ? Colors.white : Color(0xFF14221A);
  Color get raised => lightMode ? Color(0xFFEDF4EF) : Color(0xFF1B3024);
  Color get border => lightMode ? Color(0xFFD9E4DB) : Color(0xFF2B4234);
  Color get green => lightMode ? Color(0xFF286B4B) : Color(0xFF00D68A);
  Color get white => lightMode ? Color(0xFF14241A) : Color(0xFFF1F8F2);
  Color get muted => lightMode ? Color(0xFF566A5E) : Color(0xFFA2B4A7);
  static const filterValues=<String,String>{
    'all':'Tümü','online':'Son 5 dk etkin','customer':'Müşteriler','provider':'Ustalar',
    'rentacar':'Firmalar','premium':'Premium','suspended':'Askıda',
    'banned':'Engellenenler'};
  static const sortValues=<String,String>{
    'newest':'Yeni kayıtlar','oldest':'Eski kayıtlar','active':'Son hareket',
    'login':'Son giriş','name':'İsme göre'};
  bool recentlyActive(Map<String,dynamic> u) {
    final age=adminLastActivitySeconds(u,now:DateTime.now(),fetchedAt:activityFetchedAt);
    final suspended=u['is_suspended']==true || u['is_suspended']==1 ||
        u['is_suspended']=='1';
    return u['status']=='active' && !suspended && age!=null &&
        age>=0 && age<=300;
  }
  int getId(Map<String,dynamic> u)=>int.tryParse(u['id']?.toString() ?? '') ?? 0;
  bool flag(dynamic v)=>v==true||v==1||v=='1';
  String value(dynamic v,[String fallback='—']) {
    final s=v?.toString().trim()??'';
    return s.isEmpty?fallback:s;
  }
  String date(dynamic v) {
    final parsed=DateTime.tryParse(value(v,''));
    return parsed==null?'Kayıt yok':DateFormat('dd.MM.yyyy HH:mm').format(parsed);
  }
  String role(Map<String,dynamic> u)=>switch(u['user_type']) {
    'customer'=>'Müşteri','provider'=>'Usta','rentacar'=>'Rent a Car',_=>'Üye'};
  Color roleColor(Map<String,dynamic> u)=>switch(u['user_type']) {
    'provider'=>lightMode ? Color(0xFF156C9F) : Color(0xFF68C8FF),
    'rentacar'=>lightMode ? Color(0xFF956015) : Color(0xFFECC27C),_=>green};
  IconData roleIcon(Map<String,dynamic> u)=>switch(u['user_type']) {
    'provider'=>Icons.handyman_outlined,'rentacar'=>Icons.directions_car_outlined,
    _=>Icons.person_outline_rounded};
  String status(Map<String,dynamic> u) {
    if(u['status']=='banned') return 'Engelli';
    if(flag(u['is_suspended'])) return 'Askıda';
    if(u['status']=='pending') return 'Onay bekliyor';
    return 'Aktif';
  }
  Color statusColor(Map<String,dynamic> u)=>u['status']=='banned'
    ?(lightMode ? Color(0xFFBF3342) : Color(0xFFFF777B))
    :(flag(u['is_suspended'])||u['status']=='pending'
    ?(lightMode ? Color(0xFF8A6319) : Color(0xFFF4C674)):green);
  Widget pill(String label,Color color)=>Container(
    padding:const EdgeInsets.symmetric(horizontal:8,vertical:5),
    decoration:BoxDecoration(color:color.withValues(alpha:.12),
      borderRadius:BorderRadius.circular(8),
      border:Border.all(color:color.withValues(alpha:.24))),
    child:Text(label,maxLines:1,overflow:TextOverflow.ellipsis,
      style:TextStyle(color:color,fontWeight:FontWeight.w800,fontSize:10)));
  Widget avatar(Map<String,dynamic> u)=>Container(width:42,height:42,
    decoration:BoxDecoration(color:roleColor(u).withValues(alpha:.12),
      border:Border.all(color:roleColor(u).withValues(alpha:.2)),
      borderRadius:BorderRadius.circular(12)),
    child:Icon(roleIcon(u),color:roleColor(u),size:22));
  Widget summary(String title,int number,IconData icon,Color color)=>Container(
    padding:const EdgeInsets.symmetric(horizontal:13,vertical:11),
    decoration:BoxDecoration(color:surface,borderRadius:BorderRadius.circular(12),
      border:Border.all(color:border)),
    child:Row(mainAxisSize:MainAxisSize.min,children:[
      Icon(icon,color:color,size:21),SizedBox(width:10),
      Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(number.toString(),style:TextStyle(color:white,fontSize:19,
          fontWeight:FontWeight.w900)),
        Text(title,style:TextStyle(color:muted,fontSize:10)),
      ]),
    ]));
  PopupMenuItem<String> item(String key,IconData icon,String title,{bool danger=false})=>
    PopupMenuItem(value:key,child:Row(children:[
      Icon(icon,size:17,color:danger?Color(0xFFFF777B):white),
      SizedBox(width:8),
      Flexible(child:Text(title,style:TextStyle(fontSize:12,
        color:danger?Color(0xFFFF777B):white))),
    ]));
  Widget actions(Map<String,dynamic> u)=>PopupMenuButton<String>(
    tooltip:'Üye işlemleri',color:raised,
    icon:Icon(Icons.more_horiz_rounded,color:muted),
    onSelected:(action){
      switch(action) {
        case 'open':onOpen(u);
        case 'notify':onNotify(u);
        case 'docs':onDocs(u);
        case 'reviews':onReviews(u);
        case 'punish':onPunish(u);
        case 'delete':onDelete(u);
      }
    },
    itemBuilder:(_)=>[
      item('open',Icons.open_in_new_rounded,'Detaylar / araçlar / hareketler'),
      item('notify',Icons.notifications_active_outlined,'Bildirim gönder'),
      if(u['user_type']!='customer') ...[
        item('docs',Icons.folder_open_outlined,'Belgeler'),
        item('reviews',Icons.star_outline_rounded,'Profil / yorumlar'),
      ],
      item('punish',Icons.gavel_outlined,'Ceza / engelle'),
      PopupMenuDivider(),
      item('delete',Icons.delete_outline_rounded,'Üyeyi sil',danger:true),
    ]);
  Widget mobileCard(Map<String,dynamic> u) {
    final uid=getId(u),active=selected.contains(uid);
    return Material(color:active?raised:surface,
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(15),
        side:BorderSide(color:active?green:border)),
      clipBehavior:Clip.antiAlias,
      child:InkWell(onTap:bulk?()=>onToggleUser(uid):()=>onOpen(u),
        onLongPress:()=>onToggleUser(uid),
        child:Padding(padding:const EdgeInsets.all(13),child:Column(
          crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(children:[
              if(bulk) ...[
                Icon(active?Icons.check_box_rounded:Icons.check_box_outline_blank_rounded,
                  color:green),SizedBox(width:9)
              ] else ...[avatar(u),SizedBox(width:10)],
              Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(value(u['name'],'İsimsiz üye'),maxLines:1,
                  overflow:TextOverflow.ellipsis,
                  style:TextStyle(color:white,fontSize:14,fontWeight:FontWeight.w900)),
                SizedBox(height:4),
                Text('Üye #$uid · ${value(u['city'],'Şehir yok')}',
                  maxLines:1,overflow:TextOverflow.ellipsis,
                  style:TextStyle(color:muted,fontSize:11)),
              ])),
              if(!bulk)actions(u),
            ]),
            SizedBox(height:11),
            Wrap(spacing:6,runSpacing:6,children:[
              pill(role(u),roleColor(u)),pill(status(u),statusColor(u)),
               if(recentlyActive(u))pill('Son 5 dk etkin',green),
              if(flag(u['is_premium']))pill('PREMIUM',Color(0xFFF4C674)),
              if((int.tryParse(value(u['vehicle_count'],'0'))??0)>0)
                pill('${value(u['vehicle_count'])} araç',green),
            ]),
            SizedBox(height:11),
            Divider(height:1,color:border),
            SizedBox(height:10),
            Row(children:[
              Icon(Icons.phone_outlined,color:muted,size:15),
              SizedBox(width:6),
              Expanded(child:Text(value(u['phone']),maxLines:1,
                overflow:TextOverflow.ellipsis,
                style:TextStyle(color:white,fontSize:11))),
              Icon(Icons.login_rounded,color:muted,size:15),
              SizedBox(width:5),
              Flexible(child:Text(date(u['last_login_at']),
                maxLines:1,overflow:TextOverflow.ellipsis,
                style:TextStyle(color:muted,fontSize:10))),
            ]),
          ]))));
  }
  Widget desktopRow(Map<String,dynamic> u) {
    final uid=getId(u),active=selected.contains(uid);
    return Material(color:active?raised:surface,
      child:InkWell(onTap:bulk?()=>onToggleUser(uid):()=>onOpen(u),
        child:Container(padding:const EdgeInsets.fromLTRB(14,11,10,11),
          decoration:BoxDecoration(border:Border(bottom:BorderSide(color:border))),
          child:Row(children:[
            Expanded(flex:28,child:Row(children:[
              if(bulk) ...[
                Icon(active?Icons.check_box_rounded:Icons.check_box_outline_blank_rounded,
                  color:green),SizedBox(width:8)
              ] else ...[avatar(u),SizedBox(width:9)],
              Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(value(u['name'],'İsimsiz üye'),maxLines:1,
                  overflow:TextOverflow.ellipsis,
                  style:TextStyle(color:white,fontSize:12,fontWeight:FontWeight.w800)),
                SizedBox(height:4),
                Text('#$uid · ${value(u['city'],'Şehir yok')}',
                  maxLines:1,overflow:TextOverflow.ellipsis,
                  style:TextStyle(color:muted,fontSize:10)),
              ]))
            ])),
            Expanded(flex:21,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(value(u['phone']),maxLines:1,overflow:TextOverflow.ellipsis,
                style:TextStyle(color:white,fontSize:11)),
              SizedBox(height:4),
              Text(value(u['email']),maxLines:1,overflow:TextOverflow.ellipsis,
                style:TextStyle(color:muted,fontSize:10)),
            ])),
            Expanded(flex:15,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(role(u),style:TextStyle(color:roleColor(u),
                fontSize:11,fontWeight:FontWeight.w800)),
              SizedBox(height:4),
              Text('${value(u['vehicle_count'],'0')} araç',
                style:TextStyle(color:muted,fontSize:10)),
            ])),
            Expanded(flex:20,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(date(u['last_login_at']),maxLines:1,overflow:TextOverflow.ellipsis,
                style:TextStyle(color:white,fontSize:10.5)),
              SizedBox(height:4),
              Text(recentlyActive(u) ? '● Son 5 dk etkin' : 'Hareket: ${date(u['last_seen_at'])}',maxLines:1,
                overflow:TextOverflow.ellipsis,
                style:TextStyle(color:muted,fontSize:10)),
            ])),
            Expanded(flex:13,child:Align(alignment:Alignment.centerLeft,
              child:pill(status(u),statusColor(u)))),
            SizedBox(width:40,child:bulk?const SizedBox.shrink():actions(u)),
          ]))));
  }
  TextStyle get heading=>TextStyle(color:muted,fontSize:10,
    letterSpacing:.6,fontWeight:FontWeight.w900);
  @override
  Widget build(BuildContext context)=>LayoutBuilder(builder:(context,box) {
    final table=box.maxWidth>=1020, pad=box.maxWidth>=1100?25.0:14.0;
    final customer=users.where((u)=>u['user_type']=='customer').length;
    final provider=users.where((u)=>u['user_type']=='provider').length;
    final company=users.where((u)=>u['user_type']=='rentacar').length;
    return ColoredBox(color:background,child:CustomScrollView(
      physics:AlwaysScrollableScrollPhysics(),
      slivers:[
        SliverPadding(padding:EdgeInsets.fromLTRB(pad,22,pad,12),
          sliver:SliverToBoxAdapter(child:Center(child:ConstrainedBox(
            constraints:BoxConstraints(maxWidth:1450),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('OTO TAG   /   KULLANICI OPERASYONLARI',
                style:TextStyle(color:green,fontWeight:FontWeight.w900,
                  fontSize:10,letterSpacing:1.3)),
              SizedBox(height:7),
              Wrap(spacing:15,runSpacing:12,alignment:WrapAlignment.spaceBetween,
                crossAxisAlignment:WrapCrossAlignment.center,children:[
                  Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                    Text('Üye merkezi',style:TextStyle(color:white,
                      fontSize:27,fontWeight:FontWeight.w900,letterSpacing:-.6)),
                    SizedBox(height:5),
                    Text('Hesapları, araçları ve giriş kayıtlarını yönetin.',
                      style:TextStyle(color:muted,fontSize:12))
                  ]),
                  FilledButton.icon(
                    onPressed:onToggleBulk,
                    icon:Icon(bulk?Icons.close_rounded:Icons.checklist_rounded),
                    label:Text(bulk?'Seçimi bitir':'Toplu işlem'),
                    style:FilledButton.styleFrom(backgroundColor:bulk?raised:green,
                      foregroundColor:bulk?white:background)),
                ]),
              SizedBox(height:16),
              SingleChildScrollView(scrollDirection:Axis.horizontal,
                child:Row(children:[
                  summary('Yüklenen',total,Icons.groups_2_outlined,green),
                  SizedBox(width:8),
                  summary('Müşteri',customer,Icons.person_outline_rounded,green),
                  SizedBox(width:8),
                  summary('Usta',provider,Icons.handyman_outlined,
                    Color(0xFF68C8FF)),
                  SizedBox(width:8),
                  summary('Firma',company,Icons.storefront_outlined,
                    Color(0xFFECC27C)),
                ])),
              SizedBox(height:16),
              Container(padding:const EdgeInsets.all(13),
                decoration:BoxDecoration(color:surface,border:Border.all(color:border),
                  borderRadius:BorderRadius.circular(15)),
                child:Column(children:[
                  TextField(controller:searchController,onChanged:onSearch,
                    style:TextStyle(color:white,fontSize:13),
                    decoration:InputDecoration(
                      hintText:'Ad, telefon, şehir, e-posta veya üye no…',
                      hintStyle:TextStyle(color:muted,fontSize:12),
                      prefixIcon:Icon(Icons.search_rounded,color:green),
                      suffixIcon:query.isEmpty?null:IconButton(
                        onPressed:(){searchController.clear();onSearch('');},
                        icon:Icon(Icons.close_rounded,color:muted)),
                      filled:true,fillColor:background,
                      border:OutlineInputBorder(borderRadius:BorderRadius.circular(11),
                        borderSide:BorderSide(color:border)),
                      enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(11),
                        borderSide:BorderSide(color:border)),
                    )),
                  SizedBox(height:9),
                  SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(
                    children:[for(final f in filterValues.entries) ...[
                      ChoiceChip(label:Text(f.value),selected:filter==f.key,
                        showCheckmark:false,selectedColor:green,backgroundColor:background,
                        side:BorderSide(color:filter==f.key?green:border),
                        labelStyle:TextStyle(color:filter==f.key?background:muted,
                          fontSize:11,fontWeight:FontWeight.w800),
                        onSelected:(yes){if(yes)onFilter(f.key);}),
                      SizedBox(width:6),
                    ]])),
                ])),
              if(bulk) Container(
                margin:const EdgeInsets.only(top:12),
                padding:const EdgeInsets.all(12),
                decoration:BoxDecoration(color:green.withValues(alpha:.10),
                  border:Border.all(color:green.withValues(alpha:.3)),
                  borderRadius:BorderRadius.circular(12)),
                child:Wrap(spacing:8,runSpacing:7,
                  crossAxisAlignment:WrapCrossAlignment.center,children:[
                    Text('${selected.length} Seçildi',
                      style:TextStyle(color:green,fontWeight:FontWeight.w900)),
                    OutlinedButton(onPressed:onSelectAll,child:Text('Tümünü Seç')),
                    OutlinedButton(onPressed:selected.isEmpty?null:onHide,
                      child:Text('Gizle')),
                    FilledButton(onPressed:selected.isEmpty?null:onDeleteSelected,
                      style:FilledButton.styleFrom(backgroundColor:Color(0xFFC5414C)),
                      child:Text('Sil')),
                ])),
              SizedBox(height:11),
              Wrap(
                spacing:12,runSpacing:4,
                alignment:WrapAlignment.spaceBetween,
                crossAxisAlignment:WrapCrossAlignment.center,
                children:[
                  Text('${users.length} sonuç · $total kayıt',
                    style:TextStyle(color:muted,fontSize:11)),
                  if(hiddenCount>0) TextButton.icon(onPressed:onRestore,
                    icon:Icon(Icons.visibility_outlined,size:16),
                    label:Text('$hiddenCount gizlenen')),
                  Row(mainAxisSize:MainAxisSize.min,children:[
                    Icon(Icons.sort_rounded,color:muted,size:16),
                    SizedBox(width:6),
                    DropdownButtonHideUnderline(child:DropdownButton<String>(
                      value:sort,dropdownColor:raised,
                      style:TextStyle(color:white,fontSize:11),
                      items:[for(final s in sortValues.entries)
                        DropdownMenuItem(value:s.key,child:Text(s.value))],
                      onChanged:(v){if(v!=null)onSort(v);},
                    )),
                  ]),
                ]),
            ]))))),
        if(users.isEmpty)
          SliverToBoxAdapter(child:Padding(padding:EdgeInsets.all(40),
            child:Column(children:[
              Icon(Icons.person_search_rounded,size:46,color:green),
              SizedBox(height:12),
              Text('Eşleşen üye bulunamadı',style:TextStyle(color:white,
                fontSize:15,fontWeight:FontWeight.w900)),
              SizedBox(height:5),
              Text('Arama veya filtreyi değiştirin.',style:TextStyle(color:muted))
            ])))
        else ...[
          if(table)
            SliverPadding(padding:EdgeInsets.symmetric(horizontal:pad),
              sliver:SliverToBoxAdapter(child:Center(child:ConstrainedBox(
                constraints:BoxConstraints(maxWidth:1450),
                child:Container(padding:const EdgeInsets.fromLTRB(14,12,10,12),
                  decoration:BoxDecoration(color:raised,
                    borderRadius:BorderRadius.vertical(top:Radius.circular(14))),
                  child:Row(children:[
                    Expanded(flex:28,child:Text('ÜYE',style:heading)),
                    Expanded(flex:21,child:Text('İLETİŞİM',style:heading)),
                    Expanded(flex:15,child:Text('ROL / ARAÇ',style:heading)),
                    Expanded(flex:20,child:Text('SON GİRİŞ / HAREKET',style:heading)),
                    Expanded(flex:13,child:Text('DURUM',style:heading)),
                    SizedBox(width:40,child:Text('İŞLEM',style:heading)),
                  ])))))),
          SliverPadding(padding:EdgeInsets.fromLTRB(pad,0,pad,45),
            sliver:SliverList.builder(itemCount:users.length,
              itemBuilder:(context,index)=>Center(child:ConstrainedBox(
                constraints:BoxConstraints(maxWidth:1450),
                child:Padding(padding:EdgeInsets.only(bottom:table?0:10),
                  child:table?desktopRow(users[index]):mobileCard(users[index])))))),
        ],
      ]));
  });
}
