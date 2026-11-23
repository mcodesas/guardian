import 'package:flutter/material.dart';
import 'package:guardian_app/core/guardian_controller.dart';
import 'package:guardian_app/core/guardian_theme.dart';

/// Shows only workspaces explicitly linked to the authenticated account.
/// Owners can configure their policies; ADMIN can configure devices in shared
/// workspaces, VIEWER/AUTHORIZED can only read incident metadata.
class SharedWorkspacesPage extends StatefulWidget {
  const SharedWorkspacesPage({super.key, required this.controller});
  final GuardianController controller;
  @override State<SharedWorkspacesPage> createState() => _SharedWorkspacesPageState();
}
class _SharedWorkspacesPageState extends State<SharedWorkspacesPage> {
  List<Map<String, dynamic>> spaces = [], devices = [], incidents = [];
  Map<String, dynamic>? selected;
  String? error;
  bool loading = false;

  List<Map<String,dynamic>> maps(dynamic v) => (v as List)
      .map((x)=>Map<String,dynamic>.from(x as Map)).toList();

  @override void initState() {super.initState(); refreshSpaces();}

  Future<void> refreshSpaces() async {
    if(!mounted) return;
    setState(()=>loading=true);
    try {
      spaces = maps(await widget.controller.api.get('/workspaces'));
      if(mounted) setState(()=>error=null);
    } catch(e) {if(mounted) setState(()=>error='$e');}
    finally {if(mounted)setState(()=>loading=false);}
  }

  Future<void> select(Map<String,dynamic> value) async {
    setState(() {selected=value;loading=true;error=null;devices=[];incidents=[];});
    final id=value['ownerId'];
    try {
      final fetched=await Future.wait([
        widget.controller.api.get('/workspaces/$id/devices'),
        widget.controller.api.get('/workspaces/$id/incidents'),
      ]);
      if(mounted) setState(() {
        devices=maps(fetched[0]);incidents=maps(fetched[1]);
      });
    } catch(e) {if(mounted)setState(()=>error='$e');}
    finally {if(mounted)setState(()=>loading=false);}
  }

  Future<void> editPolicy(Map<String,dynamic> device) async {
    final ownerId=selected?['ownerId'];
    final deviceId=device['id'];
    if(ownerId==null||deviceId==null) return;
    var lock=device['lockOnAway']==true;
    var remote=device['allowRemoteApproval']==true;
    var seconds=device['awayTimeoutSeconds'] as int? ?? 15;
    final permittedSeconds = <int>{5,15,30,60,120,300,seconds}.toList()..sort();
    final updated=await showDialog<Map<String,dynamic>>(context:context,
      builder:(ctx)=>StatefulBuilder(builder:(ctx,redraw)=>AlertDialog(
        backgroundColor:GuardianPalette.surface,
        title:const Text('Política de equipo compartido'),
        content:Column(mainAxisSize:MainAxisSize.min,children:[
          SwitchListTile(value:lock,title:const Text('Bloquear por ausencia'),
            onChanged:(v)=>redraw(()=>lock=v)),
          DropdownButtonFormField<int>(value:seconds,
            decoration:const InputDecoration(labelText:'Segundos'),
            items:permittedSeconds.map((i)=>DropdownMenuItem(
              value:i,child:Text('$i segundos'))).toList(),
            onChanged:(v)=>redraw(()=>seconds=v??15)),
          SwitchListTile(value:remote,title:const Text('Aprobación remota'),
            onChanged:(v)=>redraw(()=>remote=v)),
        ]),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),
          ElevatedButton(onPressed:()=>Navigator.pop(ctx,{
            'lockOnAway':lock,'awayTimeoutSeconds':seconds,
            'allowRemoteApproval':remote,
          }),child:const Text('Guardar')),
        ],
      )));
    if(updated==null) return;
    try {
      await widget.controller.api.patch(
        '/workspaces/$ownerId/devices/$deviceId/policy',updated);
      if(selected!=null) await select(selected!);
    } catch(e) {
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:GuardianPalette.bg,
    appBar:AppBar(title:const Text('Espacios compartidos'),
      backgroundColor:GuardianPalette.surface),
    body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:850),
      child:ListView(padding:const EdgeInsets.all(20),children:[
        const Text('Accede únicamente a espacios a los que te hayan invitado.',
          style:TextStyle(color:GuardianPalette.muted)),
        const SizedBox(height:14),
        if(loading)const LinearProgressIndicator(),
        if(error!=null)Text(error!,style:const TextStyle(color:GuardianPalette.red)),
        for(final space in spaces) Card(child:ListTile(
          leading:const Icon(Icons.shield_outlined,color:GuardianPalette.teal),
          title:Text((space['name']??'Espacio').toString()),
          subtitle:Text('Rol: ${space['role']}'),
          selected:space['ownerId']==selected?['ownerId'],
          onTap:()=>select(space),
        )),
        const SizedBox(height:20),
        if(selected!=null) ...[
          Text('EQUIPOS DE ${selected?['name']}',style:const TextStyle(
            color:GuardianPalette.teal,fontWeight:FontWeight.w900)),
          for(final device in devices)Card(child:ListTile(
            title:Text((device['name']??'Computador').toString()),
            subtitle:Text('Estado: ${device['state']} · ${device['platform']}'),
            trailing:(selected?['role']=='ADMIN'||selected?['role']=='OWNER')
              ?IconButton(icon:const Icon(Icons.tune),onPressed:()=>editPolicy(device))
              :const Icon(Icons.visibility_outlined),
          )),
          const SizedBox(height:18),
          const Text('INCIDENTES',style:TextStyle(color:GuardianPalette.teal,
            fontWeight:FontWeight.w900)),
          if(incidents.isEmpty)const Text('No hay incidentes para mostrar.',
            style:TextStyle(color:GuardianPalette.muted)),
          for(final incident in incidents)Card(child:ListTile(
            leading:const Icon(Icons.info_outline),
            title:Text((incident['type']??'Evento').toString()),
            subtitle:Text((incident['deviceName']??'Equipo').toString()),
          )),
        ],
      ]),
    )),
  );
}
