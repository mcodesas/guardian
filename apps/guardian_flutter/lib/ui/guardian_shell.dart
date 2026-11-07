import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:guardian_app/core/guardian_controller.dart';
import 'package:guardian_app/core/guardian_theme.dart';
import 'package:guardian_app/core/mobile_approvals.dart';
import 'package:guardian_app/ui/guardian_components.dart';

class GuardianShell extends StatefulWidget {
  const GuardianShell({super.key,required this.controller});
  final GuardianController controller;
  @override State<GuardianShell> createState()=>_GuardianShellState();
}

class _GuardianShellState extends State<GuardianShell> {
  int tab=0;
  bool incidents=false, busy=false;
  int alertFilter=0;
  static const titles=['Resumen','Solicitudes','Dispositivos','Alertas','Mi cuenta'];
  static const icons=[
    Icons.dashboard_outlined,Icons.verified_user_outlined,Icons.devices_outlined,
    Icons.notifications_active_outlined,Icons.person_outline,
  ];

  void navigate(int value)=>setState(()=>tab=value);
  Future<void> action(Future<void> Function() operation) async {
    setState(()=>busy=true);
    try { await operation(); }
    catch(e) {
      if(mounted) guardianMessage(context,e.toString().replaceFirst('Bad state: ',''));
    } finally {
      if(mounted) setState(()=>busy=false);
    }
  }

  @override Widget build(BuildContext context) {
    final desktop=MediaQuery.sizeOf(context).width>=900;
    return Scaffold(
      body:SafeArea(child:Row(children:[
        if(desktop) Container(
          width:240,padding:const EdgeInsets.all(22),
          decoration:const BoxDecoration(color:GuardianPalette.surface,
            border:Border(right:BorderSide(color:GuardianPalette.line))),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Row(children:[
              GuardianLogo(size:45),SizedBox(width:12),
              Text('GUARDIAN',style:TextStyle(fontWeight:FontWeight.w900,
                letterSpacing:2,fontSize:16)),
            ]),
            const Padding(padding:EdgeInsets.only(top:14,bottom:40),
              child:Text('CENTRO DE SEGURIDAD',style:TextStyle(
                color:GuardianPalette.muted,fontSize:10,letterSpacing:1.2))),
            ...List.generate(titles.length,(i)=>Padding(
              padding:const EdgeInsets.only(bottom:7),
              child:ListTile(
                shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(15)),
                tileColor:tab==i?GuardianPalette.elevated:Colors.transparent,
                selected:tab==i,
                selectedColor:GuardianPalette.teal,
                leading:Icon(icons[i],size:21),
                title:Text(titles[i],style:const TextStyle(fontSize:13)),
                onTap:()=>navigate(i),
              ),
            )),
            const Spacer(),
            const Divider(),
            const SizedBox(height:12),
            const StatusTag('GUARDIAN ID',GuardianPalette.teal,
              icon:Icons.security_outlined),
            const SizedBox(height:14),
            const Text('Protección consciente, privacidad por diseño.',
              style:TextStyle(color:GuardianPalette.muted,fontSize:11,height:1.5)),
          ]),
        ),
        Expanded(child:RefreshIndicator(
          onRefresh:widget.controller.reload,
          child:SingleChildScrollView(
            physics:const AlwaysScrollableScrollPhysics(),
            padding:EdgeInsets.symmetric(horizontal:desktop?35:18,vertical:24),
            child:Center(child:ConstrainedBox(
              constraints:const BoxConstraints(maxWidth:1150),
              child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Row(children:[
                  if(!desktop)...[const GuardianLogo(size:39),const SizedBox(width:12)],
                  Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                    const Text('GUARDIAN  /  MCODE',
                      style:TextStyle(color:GuardianPalette.teal,
                        fontWeight:FontWeight.w800,fontSize:10,letterSpacing:1.6)),
                    const SizedBox(height:5),
                    Text(titles[tab],style:Theme.of(context).textTheme.headlineMedium),
                  ])),
                  IconButton(tooltip:'Actualizar',onPressed:widget.controller.reload,
                    icon:const Icon(Icons.refresh,color:GuardianPalette.muted)),
                  IconButton(tooltip:'Alertas',onPressed:()=>navigate(3),
                    icon:Badge(
                      isLabelVisible:widget.controller.unread>0,
                      label:Text(widget.controller.unread.toString()),
                      child:const Icon(Icons.notifications_none,color:GuardianPalette.white))),
                ]),
                const SizedBox(height:26),
                if(tab==0) _home(),
                if(tab==1) _approvals(),
                if(tab==2) _devices(),
                if(tab==3) _notifications(),
                if(tab==4) _profile(),
                const SizedBox(height:45),
                const Center(child:Text('GUARDIAN  •  by MCode',
                  style:TextStyle(color:GuardianPalette.muted,letterSpacing:2,fontSize:10))),
              ]),
            )),
          ),
        )),
      ])),
      bottomNavigationBar:desktop?null:NavigationBar(
        height:72,selectedIndex:tab,
        onDestinationSelected:navigate,
        destinations:List.generate(titles.length,(i)=>NavigationDestination(
          icon:Icon(icons[i],size:22),
          label:['Inicio','Aprobar','Equipos','Alertas','Cuenta'][i],
        )),
      ),
    );
  }

  Widget _home()=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Container(width:double.infinity,padding:const EdgeInsets.all(26),
      decoration:BoxDecoration(
        gradient:const LinearGradient(colors:[
          Color(0xFF17434D),Color(0xFF122F40),Color(0xFF122232)],
          begin:Alignment.topLeft,end:Alignment.bottomRight),
        borderRadius:BorderRadius.circular(25),
        border:Border.all(color:GuardianPalette.teal.withValues(alpha:.22)),
      ),
      child:Row(children:[
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const StatusTag('CENTRO DE CONTROL',GuardianPalette.teal,
            icon:Icons.shield_outlined),
          const SizedBox(height:18),
          const Text('Tu seguridad,\nen tus manos.',style:TextStyle(
            color:GuardianPalette.white,fontSize:29,
            fontWeight:FontWeight.w900,height:1.14)),
          const SizedBox(height:11),
          const Text('Todos tus dispositivos y alertas en un solo lugar.',
            style:TextStyle(color:GuardianPalette.muted,height:1.4)),
          const SizedBox(height:18),
          OutlinedButton.icon(onPressed:()=>navigate(2),
            icon:const Icon(Icons.add),label:const Text('Agregar un equipo')),
        ])),
        if(MediaQuery.sizeOf(context).width>=680)
          const Icon(Icons.shield_rounded,size:125,color:GuardianPalette.teal),
      ]),
    ),
    const SizedBox(height:22),
    LayoutBuilder(builder:(ctx,box){
      final columns=box.maxWidth>=720?3:box.maxWidth>=420?2:1;
      final width=(box.maxWidth-(columns-1)*12)/columns;
      return Wrap(spacing:12,runSpacing:12,children:[
        _stat('Mis computadores',widget.controller.devices.length.toString(),
          Icons.computer,GuardianPalette.blue,width),
        _stat('Pendientes',widget.controller.pending.toString(),
          Icons.how_to_reg_outlined,GuardianPalette.amber,width),
        _stat('Alertas sin leer',widget.controller.unread.toString(),
          Icons.notifications_active_outlined,GuardianPalette.red,width),
      ]);
    }),
    const SizedBox(height:30),
    SectionTitle('Estado de tus equipos',
      trailing:TextButton(onPressed:()=>navigate(2),child:const Text('Ver todos'))),
    const SizedBox(height:13),
    if(widget.controller.devices.isEmpty)
      const GuardianEmpty(title:'Todavía no hay equipos',
        description:'Registra un computador. Solo quedará protegido cuando vincules y actives el agente nativo.',
        icon:Icons.laptop_mac_outlined),
    ...widget.controller.devices.take(3).map((d)=>Padding(
      padding:const EdgeInsets.only(bottom:12),child:_deviceCard(d,compact:true))),
    const SizedBox(height:28),
    SectionTitle('Novedades de seguridad',
      trailing:TextButton(onPressed:()=>navigate(3),child:const Text('Ver alertas'))),
    const SizedBox(height:13),
    if(widget.controller.notifications.isEmpty)
      const GuardianEmpty(title:'Todo en calma',
        description:'Aquí aparecerán las solicitudes e incidentes que reporten tus dispositivos.',
        icon:Icons.check_circle_outline),
    ...widget.controller.notifications.take(3).map((n)=>Padding(
      padding:const EdgeInsets.only(bottom:12),child:_notificationCard(n))),
  ]);

  Widget _stat(String title,String count,IconData icon,Color color,double width)=>
    SizedBox(width:width,child:GlassCard(child:Column(
      crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[Expanded(child:Text(title,
          style:const TextStyle(color:GuardianPalette.muted,fontSize:12))),
          Icon(icon,color:color,size:22)]),
        const SizedBox(height:18),
        Text(count,style:const TextStyle(fontSize:34,fontWeight:FontWeight.w900)),
        const SizedBox(height:5),
        Text('En Guardian',style:TextStyle(color:color,fontSize:11)),
      ])));

  Widget _approvals(){
    final pending=widget.controller.approvals.where((it)=>
      it['state']=='PENDING' &&
      (DateTime.tryParse((it['expiresAt']??'').toString())?.isAfter(DateTime.now())??false))
      .toList();
    final historic=widget.controller.approvals.where((it)=>!pending.contains(it)).toList();
    final mobile=Platform.isAndroid||Platform.isIOS;
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('Autoriza únicamente las solicitudes que reconozcas. '
        'La aprobación no desbloquea el sistema operativo.',
        style:TextStyle(color:GuardianPalette.muted,height:1.5)),
      const SizedBox(height:18),
      SectionTitle('Esperando aprobación',
        subtitle:'El equipo se protege localmente si no respondes'),
      const SizedBox(height:14),
      if(pending.isEmpty)
        const GuardianEmpty(title:'Ninguna solicitud pendiente',
          description:'Cuando un equipo no logre verificar al propietario, aparecerá su solicitud aquí.',
          icon:Icons.verified_user_outlined),
      ...pending.map((item)=>Padding(padding:const EdgeInsets.only(bottom:14),
        child:GlassCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[
            const Icon(Icons.gpp_maybe_outlined,color:GuardianPalette.amber,size:31),
            const SizedBox(width:12),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text((item['deviceName']??'Equipo').toString(),
                style:Theme.of(context).textTheme.titleMedium),
              Text('Creada: '+friendlyTime(item['createdAt']),
                style:const TextStyle(color:GuardianPalette.muted,fontSize:12)),
            ])),
            const StatusTag('PENDIENTE',GuardianPalette.amber),
          ]),
          const SizedBox(height:15),
          const Text('No se pudo confirmar el rostro. ¿Reconoces la actividad de este equipo?',
            style:TextStyle(color:GuardianPalette.muted,height:1.5)),
          const SizedBox(height:15),
          if(mobile) Wrap(spacing:10,runSpacing:10,children:[
            ElevatedButton.icon(onPressed:busy?null:()=>_reply(item,true),
              icon:const Icon(Icons.check_circle_outline),
              label:const Text('Aprobar acceso')),
            OutlinedButton.icon(onPressed:busy?null:()=>_reply(item,false),
              icon:const Icon(Icons.lock_outline,color:GuardianPalette.red),
              label:const Text('Rechazar')),
          ]) else const Text('Responde desde Android o iOS con huella o Face ID.',
            style:TextStyle(color:GuardianPalette.amber,fontSize:12)),
        ])))),
      const SizedBox(height:28),
      const SectionTitle('Historial de decisiones'),
      const SizedBox(height:14),
      if(historic.isEmpty)const GuardianEmpty(title:'Aún no hay decisiones',
        description:'Las autorizaciones anteriores estarán disponibles aquí.',
        icon:Icons.history_outlined),
      ...historic.take(25).map((item)=>Padding(
        padding:const EdgeInsets.only(bottom:10),
        child:GlassCard(child:Row(children:[
          const Icon(Icons.history,color:GuardianPalette.muted),
          const SizedBox(width:12),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text((item['deviceName']??'Equipo').toString(),
              style:const TextStyle(fontWeight:FontWeight.w800)),
            Text(friendlyTime(item['createdAt']),
              style:const TextStyle(color:GuardianPalette.muted,fontSize:11)),
          ])),
          StatusTag((item['state']??'').toString(),
            item['state']=='APPROVED'?GuardianPalette.teal:GuardianPalette.muted),
        ])))),
    ]);
  }

  Future<void> _reply(Map<String,dynamic> item,bool approve) async {
    var minutes=0;
    if(approve){
      final selected=await showModalBottomSheet<int>(context:context,
        backgroundColor:GuardianPalette.surface,showDragHandle:true,
        builder:(ctx)=>SafeArea(child:Padding(padding:const EdgeInsets.all(24),
          child:Column(mainAxisSize:MainAxisSize.min,
            crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('Autorizar temporalmente',style:TextStyle(
              fontWeight:FontWeight.w900,fontSize:23)),
            const SizedBox(height:8),
            const Text('La autorización caduca y puede revocarse ante una intrusión.',
              style:TextStyle(color:GuardianPalette.muted)),
            const SizedBox(height:14),
            for(final value in [5,15,30]) ListTile(
              title:Text('$value minutos'),leading:const Icon(Icons.timer_outlined,
                color:GuardianPalette.teal),
              trailing:const Icon(Icons.chevron_right),
              onTap:()=>Navigator.pop(ctx,value)),
          ]),
        ))
      );
      if(selected==null) return;
      minutes=selected;
    }
    await action(()async{
      final accountId=(widget.controller.profile?['id']??'').toString();
      await MobileApprovals(widget.controller.api,accountId).decide(item,
        approve:approve,minutes:minutes);
      await widget.controller.reload();
      if(mounted) guardianMessage(context,approve?'Acceso autorizado temporalmente.':
        'Solicitud rechazada.');
    });
  }

  Widget _devices()=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    SectionTitle('Computadores registrados',
      subtitle:'Cada equipo debe vincularse con un agente nativo',
      trailing:ElevatedButton.icon(onPressed:busy?null:_addDevice,
        icon:const Icon(Icons.add),label:const Text('Agregar'))),
    const SizedBox(height:14),
    if(widget.controller.devices.isEmpty)const GuardianEmpty(
      title:'Comienza con tu primer computador',
      description:'Regístralo y vincula su agente para administrar sus políticas.',
      icon:Icons.desktop_windows_outlined),
    ...widget.controller.devices.map((d)=>Padding(
      padding:const EdgeInsets.only(bottom:12),child:_deviceCard(d))),
    const SizedBox(height:14),
    const GlassCard(child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Icon(Icons.info_outline,color:GuardianPalette.amber),
      SizedBox(width:12),
      Expanded(child:Text('Un registro pendiente no significa que Guardian esté '
        'bloqueando el computador. La protección requiere el agente nativo instalado.',
        style:TextStyle(color:GuardianPalette.muted,height:1.5,fontSize:12))),
    ])),
  ]);

  Widget _deviceCard(Map<String,dynamic> d,{bool compact=false}) {
    final linked=d['state']=='PAIRED';
    final platform=(d['platform']??'').toString();
    return GlassCard(child:Column(children:[
      Row(children:[
        Container(width:48,height:48,
          decoration:BoxDecoration(color:GuardianPalette.elevated,
            borderRadius:BorderRadius.circular(15)),
          child:Icon(platform=='MACOS'?Icons.laptop_mac_rounded:
            Icons.desktop_windows_rounded,color:GuardianPalette.blue)),
        const SizedBox(width:13),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text((d['name']??'Equipo').toString(),
            style:const TextStyle(fontWeight:FontWeight.w800)),
          const SizedBox(height:3),
          Text(platform,style:const TextStyle(color:GuardianPalette.muted,fontSize:12)),
        ])),
        StatusTag(linked?'VINCULADO':'SIN AGENTE',
          linked?GuardianPalette.teal:GuardianPalette.amber),
      ]),
      if(!compact)...[
        const SizedBox(height:13),const Divider(),
        Row(children:[
          const Icon(Icons.lock_clock_outlined,color:GuardianPalette.muted,size:18),
          const SizedBox(width:8),
          Expanded(child:Text(d['lockOnAway']==true
            ? 'Bloquear por ausencia: '+d['awayTimeoutSeconds'].toString()+' s'
            : 'Bloqueo por ausencia desactivado',
            style:const TextStyle(color:GuardianPalette.muted,fontSize:12))),
          IconButton(onPressed:()=>_configure(d),tooltip:'Configurar',
            icon:const Icon(Icons.tune_rounded,color:GuardianPalette.teal)),
          IconButton(onPressed:()=>_revoke(d),tooltip:'Revocar',
            icon:const Icon(Icons.delete_outline,color:GuardianPalette.red)),
        ]),
      ],
    ]));
  }

  Future<void> _addDevice() async {
    final name=TextEditingController();
    var platform='WINDOWS';
    final result=await showDialog<Map<String,String>>(context:context,
      builder:(ctx)=>StatefulBuilder(builder:(ctx,rebuild)=>AlertDialog(
        backgroundColor:GuardianPalette.surface,
        title:const Text('Nuevo computador'),
        content:ConstrainedBox(constraints:const BoxConstraints(maxWidth:400),
          child:Column(mainAxisSize:MainAxisSize.min,children:[
            TextField(controller:name,decoration:const InputDecoration(
              labelText:'Nombre',hintText:'Mi computador')),
            const SizedBox(height:15),
            DropdownButtonFormField<String>(initialValue:platform,
              decoration:const InputDecoration(labelText:'Sistema operativo'),
              items:const[
                DropdownMenuItem(value:'WINDOWS',child:Text('Windows')),
                DropdownMenuItem(value:'MACOS',child:Text('macOS')),
                DropdownMenuItem(value:'LINUX',child:Text('Linux')),
              ],
              onChanged:(v)=>rebuild(()=>platform=v??'WINDOWS')),
          ])),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),
          ElevatedButton(onPressed:()=>Navigator.pop(ctx,{
            'name':name.text.trim(),'platform':platform,
          }),child:const Text('Registrar')),
        ],
      )));
    name.dispose();
    if(result==null || (result['name']??'').isEmpty) return;
    await action(()async{
      final created=await widget.controller.addDevice(
        result['name']!,result['platform']!);
      if(!mounted) return;
      final secret=(created['agentKey']??'').toString();
      await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
        backgroundColor:GuardianPalette.surface,
        title:const Text('Clave para el agente'),
        content:ConstrainedBox(constraints:const BoxConstraints(maxWidth:420),
          child:Column(mainAxisSize:MainAxisSize.min,children:[
            const Text('Este secreto solo se muestra una vez. '
              'Almacénalo en el equipo protegido, no en un documento compartido.',
              style:TextStyle(color:GuardianPalette.muted)),
            const SizedBox(height:17),
            SelectableText(secret,style:const TextStyle(
              fontSize:12,color:GuardianPalette.teal)),
          ])),
        actions:[
          TextButton(onPressed:()async{
            await Clipboard.setData(ClipboardData(text:secret));
            if(ctx.mounted) guardianMessage(ctx,'Clave copiada; limpia el portapapeles al terminar.');
          },child:const Text('Copiar')),
          ElevatedButton(onPressed:()=>Navigator.pop(ctx),
            child:const Text('Entendido')),
        ],
      ));
    });
  }

  Future<void> _configure(Map<String,dynamic> d) async {
    var lock=d['lockOnAway']==true;
    var remote=d['allowRemoteApproval']==true;
    var seconds=(d['awayTimeoutSeconds'] as int?)??15;
    final result=await showDialog<Map<String,dynamic>>(context:context,
      builder:(ctx)=>StatefulBuilder(builder:(ctx,rebuild)=>AlertDialog(
        backgroundColor:GuardianPalette.surface,
        title:const Text('Políticas de protección'),
        content:ConstrainedBox(constraints:const BoxConstraints(maxWidth:430),
          child:SingleChildScrollView(child:Column(
            mainAxisSize:MainAxisSize.min,children:[
            SwitchListTile.adaptive(value:lock,onChanged:(v)=>rebuild(()=>lock=v),
              title:const Text('Bloquear por ausencia')),
            const SizedBox(height:10),
            DropdownButtonFormField<int>(initialValue:seconds,
              decoration:const InputDecoration(labelText:'Segundos de ausencia'),
              items:[5,15,30,60,120,300].map((s)=>
                DropdownMenuItem(value:s,child:Text('$s segundos'))).toList(),
              onChanged:(v)=>rebuild(()=>seconds=v??15)),
            const SizedBox(height:10),
            SwitchListTile.adaptive(value:remote,onChanged:(v)=>rebuild(()=>remote=v),
              title:const Text('Aprobación desde celular')),
          ]))),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),
          ElevatedButton(onPressed:()=>Navigator.pop(ctx,{
            'lock':lock,'remote':remote,'seconds':seconds,
          }),child:const Text('Guardar')),
        ],
      )));
    if(result==null) return;
    await action(()=>widget.controller.updatePolicy(d['id'] as String,
      lockOnAway:result['lock'] as bool,
      seconds:result['seconds'] as int,
      remoteApproval:result['remote'] as bool));
  }

  Future<void> _revoke(Map<String,dynamic> d) async {
    final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      backgroundColor:GuardianPalette.surface,title:const Text('Revocar equipo'),
      content:const Text('La clave del agente quedará invalidada y se '
        'cancelarán las solicitudes pendientes.'),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),
        ElevatedButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Revocar')),
      ],
    ));
    if(confirmed==true) await action(()=>
      widget.controller.revokeDevice(d['id'] as String));
  }

  List<Map<String,dynamic>> get _filteredNotifications {
    final items=widget.controller.notifications;
    if(alertFilter==1) {
      return items.where((it)=>it['type']=='INTRUSION').toList();
    }
    if(alertFilter==2) {
      return items.where((it)=>it['type']=='APPROVAL_REQUIRED').toList();
    }
    if(alertFilter==3) {
      return items.where((it)=>it['type']!='APPROVAL_REQUIRED' &&
        it['type']!='INTRUSION').toList();
    }
    return items;
  }

  Widget _notifications()=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    const Text('Avisos, solicitudes e incidentes de tus dispositivos.',
      style:TextStyle(color:GuardianPalette.muted)),
    const SizedBox(height:16),
    Wrap(spacing:10,children:[
      ChoiceChip(label:const Text('Notificaciones'),selected:!incidents,
        onSelected:(_)=>setState(()=>incidents=false)),
      ChoiceChip(label:const Text('Incidentes'),selected:incidents,
        onSelected:(_)=>setState(()=>incidents=true)),
    ]),
    const SizedBox(height:16),
    if(!incidents) ...[
      const Text('FILTRAR POR TIPO',style:TextStyle(
        color:GuardianPalette.muted,fontSize:10,letterSpacing:1.5)),
      const SizedBox(height:9),
      Wrap(spacing:8,runSpacing:8,children:[
        for(final entry in <(String,int)>[
            ('Todas',0),('Críticas',1),('Solicitudes',2),('Estado de equipos',3)
          ])
          ChoiceChip(label:Text(entry.$1),selected:alertFilter==entry.$2,
            onSelected:(_)=>setState(()=>alertFilter=entry.$2)),
      ]),
      const SizedBox(height:18),
    ],
    if(!incidents && _filteredNotifications.isEmpty)
      const GuardianEmpty(title:'No hay avisos en esta categoría',
        description:'Cuando Guardian registre una alerta, aparecerá aquí. '
          'También puedes seleccionar el filtro Todas.',
        icon:Icons.notifications_none_outlined),
    if(!incidents)..._filteredNotifications.map((n)=>Padding(
      padding:const EdgeInsets.only(bottom:12),child:_notificationCard(n))),
    if(incidents && widget.controller.incidents.isEmpty)
      const GuardianEmpty(title:'Sin incidentes',
        description:'Los eventos de seguridad de los agentes registrados se mostrarán aquí.',
        icon:Icons.health_and_safety_outlined),
    if(incidents)...widget.controller.incidents.map((event)=>Padding(
      padding:const EdgeInsets.only(bottom:12),
      child:GlassCard(child:Row(children:[
        const Icon(Icons.report_problem_outlined,color:GuardianPalette.amber,size:29),
        const SizedBox(width:13),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text((event['type']??'Evento').toString(),
            style:const TextStyle(fontWeight:FontWeight.w800)),
          const SizedBox(height:5),
          Text((event['deviceName']??'Equipo').toString()+
            ' · '+friendlyTime(event['occurredAt']),
            style:const TextStyle(color:GuardianPalette.muted,fontSize:12)),
        ])),
      ])))),
  ]);

  Widget _notificationCard(Map<String,dynamic> n) {
    final critical=n['type']=='INTRUSION';
    final request=n['type']=='APPROVAL_REQUIRED';
    final color=critical?GuardianPalette.red:
      request?GuardianPalette.amber:GuardianPalette.blue;
    return GestureDetector(
      onTap:()=>_notificationDetail(n),
      child:GlassCard(child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Container(width:45,height:45,decoration:BoxDecoration(
        color:color.withValues(alpha:.12),borderRadius:BorderRadius.circular(15)),
        child:Icon(critical?Icons.gpp_bad_outlined:
          request?Icons.how_to_reg_outlined:Icons.notifications_active_outlined,color:color)),
      const SizedBox(width:13),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[
          Expanded(child:Text((n['title']??'Aviso').toString(),
            style:const TextStyle(fontWeight:FontWeight.w800))),
          if(n['read']==false) Container(width:9,height:9,
            decoration:BoxDecoration(color:color,shape:BoxShape.circle)),
        ]),
        const SizedBox(height:7),
        Text((n['body']??'').toString(),
          style:const TextStyle(color:GuardianPalette.muted,fontSize:12,height:1.6)),
        const SizedBox(height:7),
        Text(friendlyTime(n['createdAt']),
          style:const TextStyle(color:GuardianPalette.blue,fontSize:11)),
        if(request) TextButton(onPressed:()=>navigate(1),
          child:const Text('Ver solicitud')),
      ])),
      if(n['read']==false) IconButton(tooltip:'Marcar como leída',
        onPressed:busy?null:()=>action(()=>
          widget.controller.markRead(n['id'] as String)),
        icon:const Icon(Icons.done_all,color:GuardianPalette.teal,size:20)),
    ])));
  }

  Future<void> _notificationDetail(Map<String,dynamic> notice) async {
    final critical=notice['type']=='INTRUSION';
    final requested=notice['type']=='APPROVAL_REQUIRED';
    final color=critical?GuardianPalette.red:
      requested?GuardianPalette.amber:GuardianPalette.blue;
    final title=(notice['title']??'Notificación').toString();
    final body=(notice['body']??'').toString();
    await showModalBottomSheet<void>(
      context:context,backgroundColor:GuardianPalette.surface,
      showDragHandle:true,isScrollControlled:true,
      builder:(sheet)=>SafeArea(child:Padding(
        padding:EdgeInsets.fromLTRB(22,10,22,
          24+MediaQuery.viewInsetsOf(sheet).bottom),
        child:ConstrainedBox(constraints:const BoxConstraints(maxHeight:510),
          child:SingleChildScrollView(child:Column(
            mainAxisSize:MainAxisSize.min,
            crossAxisAlignment:CrossAxisAlignment.start,children:[
              Row(children:[
                Container(width:54,height:54,
                  decoration:BoxDecoration(color:color.withValues(alpha:.12),
                    borderRadius:BorderRadius.circular(18)),
                  child:Icon(critical?Icons.shield_outlined:
                    requested?Icons.phonelink_lock_rounded:
                    Icons.notifications_active_outlined,
                    size:29,color:color)),
                const SizedBox(width:14),
                Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
                  children:[
                    Text(title,style:Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height:4),
                    Text(friendlyTime(notice['createdAt']),
                      style:const TextStyle(color:GuardianPalette.muted)),
                  ])),
              ]),
              const SizedBox(height:19),
              StatusTag(critical?'SEGURIDAD CRÍTICA':
                requested?'SOLICITUD DE ACCESO':'INFORMACIÓN DEL EQUIPO',
                color,icon:critical?Icons.warning_amber:
                  requested?Icons.verified_user_outlined:Icons.info_outline),
              const SizedBox(height:19),
              GlassCard(child:Text(body,style:const TextStyle(
                height:1.6,color:GuardianPalette.white,fontSize:14))),
              const SizedBox(height:16),
              Text(critical
                ?'Comprueba el incidente antes de tomar decisiones. '
                  'No compartas contraseñas ni códigos por correo.'
                :requested
                  ?'Una aprobación exige un teléfono previamente vinculado '
                    'y autenticación biométrica.'
                  :'Puedes revisar el estado y las políticas del dispositivo.',
                style:const TextStyle(
                  color:GuardianPalette.muted,fontSize:12,height:1.5)),
              const SizedBox(height:24),
              SizedBox(width:double.infinity,child:ElevatedButton.icon(
                onPressed:(){
                  Navigator.pop(sheet);
                  if(requested)navigate(1);
                  else if(!critical)navigate(2);
                },
                icon:Icon(requested?Icons.verified_user_outlined:
                  critical?Icons.check_circle_outline:Icons.devices_outlined),
                label:Text(requested?'Revisar y responder':
                  critical?'Entendido':'Ver dispositivos'),
              )),
              if(notice['read']==false)...[
                const SizedBox(height:10),
                SizedBox(width:double.infinity,
                  child:OutlinedButton.icon(
                    onPressed:(){
                      Navigator.pop(sheet);
                      action(()=>widget.controller.markRead(notice['id'] as String));
                    },
                    icon:const Icon(Icons.done_all),
                    label:const Text('Marcar como leída')),
                ),
              ],
            ])),
        )),
      ),
    );
  }

  Future<void> _enrollPhone() async {
    await action(() async {
      final accountId=(widget.controller.profile?['id']??'').toString();
      final approval=MobileApprovals(widget.controller.api,accountId);
      if(!approval.supported) {
        throw StateError('La vinculación debe realizarse en Android o iOS.');
      }
      if(await approval.isEnrolled()) {
        if(mounted) guardianMessage(context,'Este teléfono ya está vinculado.');
        return;
      }
      await approval.sendEnrollmentCode();
      if(!mounted) return;

      final codeController=TextEditingController();
      String? code;
      try {
        code=await showDialog<String>(context:context,
          builder:(ctx)=>AlertDialog(
            backgroundColor:GuardianPalette.surface,
            title:const Text('Vincula tu teléfono'),
            content:ConstrainedBox(
              constraints:const BoxConstraints(maxWidth:380),
              child:SingleChildScrollView(child:Column(
                mainAxisSize:MainAxisSize.min,
                crossAxisAlignment:CrossAxisAlignment.start,children:[
                const Icon(Icons.mark_email_read_outlined,
                  color:GuardianPalette.teal,size:40),
                const SizedBox(height:15),
                const Text('Enviamos un código al correo verificado '
                  'de tu cuenta Guardian. Solo podrás aprobar accesos '
                  'después de completar esta vinculación.',
                  style:TextStyle(color:GuardianPalette.muted,height:1.5)),
                const SizedBox(height:17),
                TextField(controller:codeController,
                  autofocus:true,
                  keyboardType:TextInputType.number,
                  maxLength:6,
                  decoration:const InputDecoration(
                    labelText:'Código de seis dígitos',
                    prefixIcon:Icon(Icons.pin_outlined),
                    counterText:'')),
                const SizedBox(height:8),
                const Text('Después solicitaremos huella o Face ID.',
                  style:TextStyle(color:GuardianPalette.amber,fontSize:12)),
              ])),
            ),
            actions:[
              TextButton(onPressed:()=>Navigator.pop(ctx),
                child:const Text('Cancelar')),
              ElevatedButton(
                onPressed:()=>Navigator.pop(ctx,codeController.text.trim()),
                child:const Text('Vincular')),
            ],
          ));
      } finally {
        // Closing the dialog completes its route, after which its controller
        // is no longer needed.
        codeController.dispose();
      }
      if(code==null) return;
      await approval.enroll(code);
      await widget.controller.push.start(widget.controller.api,
        widget.controller.reload,accountId);
      if(mounted) {
        setState(() {});
        guardianMessage(context,
          'Teléfono vinculado. Ya puedes aprobar accesos con biometría.');
      }
    });
  }

  Widget _profile()=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    GlassCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Row(children:[
        GuardianLogo(size:48),SizedBox(width:12),
        Expanded(child:Text('Guardian ID',
          style:TextStyle(fontSize:21,fontWeight:FontWeight.w900))),
        StatusTag('VERIFICADA',GuardianPalette.teal,icon:Icons.verified_outlined),
      ]),
      const SizedBox(height:25),
      Text((widget.controller.profile?['name']??'Propietario').toString(),
        style:Theme.of(context).textTheme.titleLarge),
      const SizedBox(height:6),
      Text((widget.controller.profile?['email']??'').toString(),
        style:const TextStyle(color:GuardianPalette.muted)),
      const SizedBox(height:20),const Divider(),
      const SizedBox(height:13),
      const Text('Servidor conectado',
        style:TextStyle(color:GuardianPalette.muted,fontSize:12)),
      const SizedBox(height:6),
      SelectableText(widget.controller.api.serverUrl),
      const SizedBox(height:21),
      StatusTag(widget.controller.push.ready?'PUSH ACTIVO':'PUSH SIN CONFIGURAR',
        widget.controller.push.ready?GuardianPalette.teal:GuardianPalette.amber,
        icon:Icons.notifications_outlined),
      const SizedBox(height:19),
      if(Platform.isAndroid || Platform.isIOS) ...[
        FutureBuilder<bool>(
          future:MobileApprovals(widget.controller.api,
              (widget.controller.profile?['id']??'').toString()).isEnrolled(),
          builder:(context,snapshot)=>Column(
            crossAxisAlignment:CrossAxisAlignment.start,children:[
              StatusTag(snapshot.data==true?'MÓVIL VINCULADO':'PENDIENTE DE VINCULACIÓN',
                snapshot.data==true?GuardianPalette.teal:GuardianPalette.amber,
                icon:Icons.fingerprint_outlined),
              const SizedBox(height:12),
              OutlinedButton.icon(onPressed:busy?null:_enrollPhone,
                icon:const Icon(Icons.phonelink_lock_outlined),
                label:Text(snapshot.data==true?
                  'Consultar vinculación':'Vincular este teléfono')),
              const SizedBox(height:18),
            ]),
        ),
      ],
      OutlinedButton.icon(onPressed:busy?null:()=>action(widget.controller.logout),
        icon:const Icon(Icons.logout_outlined,color:GuardianPalette.red),
        label:const Text('Cerrar sesión')),
    ])),
    const SizedBox(height:19),
    const GuardianEmpty(title:'Tu privacidad es prioridad',
      description:'Guardian no desbloquea el sistema operativo por su cuenta. '
        'Las funciones de protección facial requieren instalación del agente local.',
      icon:Icons.privacy_tip_outlined),
  ]);
}
