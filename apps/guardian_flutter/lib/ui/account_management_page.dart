import 'package:flutter/material.dart';
import 'package:guardian_app/core/guardian_controller.dart';
import 'package:guardian_app/core/api.dart';
import 'package:guardian_app/core/guardian_theme.dart';

/// Account administration is always scoped to the signed-in Guardian identity.
/// Destructive operations are confirmed by password and (for deletion) email OTP.
class AccountManagementPage extends StatefulWidget {
  const AccountManagementPage({super.key, required this.controller});
  final GuardianController controller;
  @override State<AccountManagementPage> createState() => _AccountManagementPageState();
}

class _AccountManagementPageState extends State<AccountManagementPage> {
  Map<String, dynamic> account = {};
  List<Map<String, dynamic>> sessions = [], members = [], invitations = [];
  int section = 0;
  bool loading = false, saving = false;
  String? error;
  static const roles = ['VIEWER', 'AUTHORIZED', 'ADMIN'];

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { loading = true; error = null; });
    try {
      final responses = await Future.wait([
        widget.controller.api.get('/account'),
        widget.controller.api.get('/account/sessions'),
        widget.controller.api.get('/account/members'),
        widget.controller.api.get('/account/invitations'),
      ]);
      if (mounted) setState(() {
        account = Map<String, dynamic>.from(responses[0] as Map);
        sessions = _items(responses[1]);
        members = _items(responses[2]);
        invitations = _items(responses[3]);
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<Map<String, dynamic>> _items(dynamic value) =>
      (value as List).map((i) => Map<String,dynamic>.from(i as Map)).toList();

  Future<void> _action(Future<void> Function() task) async {
    if (!mounted) return;
    setState(() => saving = true);
    try {
      await task();
      if (widget.controller.authenticated) await _load();
    } catch (e) {
      if (mounted) _message(e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<String?> _prompt(String title, String label, {bool secret=false,
      String initial='', String? description}) async {
    final field = TextEditingController(text: initial);
    try {
      return await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
        backgroundColor: GuardianPalette.surface,
        title: Text(title),
        content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430),
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (description != null) ...[
                Text(description, style: const TextStyle(color: GuardianPalette.muted)),
                const SizedBox(height: 14),
              ],
              TextField(controller: field, obscureText: secret,
                  enableSuggestions: !secret, autocorrect: !secret,
                  decoration: InputDecoration(labelText: label)),
            ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx,field.text),
              child: const Text('Continuar')),
        ],
      ));
    } finally { field.dispose(); }
  }

  Future<bool> _confirm(String title, String description) async {
    return await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: GuardianPalette.surface,
      title: Text(title), content: Text(description),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx,false), child: const Text('Cancelar')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx,true), child: const Text('Confirmar')),
      ],
    )) ?? false;
  }

  Future<void> _editProfile() async {
    final name = TextEditingController(text: (account['name'] ?? '').toString());
    final phone = TextEditingController(text: (account['phone'] ?? '').toString());
    try {
      final update = await showDialog<Map<String, String>>(context:context,
        builder:(ctx)=>AlertDialog(
          backgroundColor: GuardianPalette.surface,
          title: const Text('Editar información personal'),
          content: ConstrainedBox(constraints: const BoxConstraints(maxWidth:430),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller:name, decoration:const InputDecoration(labelText:'Nombre')),
              const SizedBox(height:14),
              TextField(controller:phone, keyboardType:TextInputType.phone,
                decoration:const InputDecoration(labelText:'Teléfono (opcional)')),
            ])),
          actions:[
            TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),
            ElevatedButton(onPressed:()=>Navigator.pop(ctx,{
              'name':name.text.trim(), 'phone':phone.text.trim(),
            }),child:const Text('Guardar')),
          ],
        ));
      if(update == null) return;
      await _action(() async {
        await widget.controller.api.patch('/account',update);
        _message('Perfil actualizado');
      });
    } finally { name.dispose(); phone.dispose(); }
  }

  Future<void> _changePassword() async {
    final current = await _prompt('Contraseña actual','Contraseña',secret:true);
    if(current == null) return;
    final next = await _prompt('Cambiar contraseña',
        'Nueva contraseña (mínimo 12 caracteres)',secret:true);
    if(next == null) return;
    if(next.length < 12) { _message('Utiliza al menos 12 caracteres'); return; }
    await _action(() async {
      await widget.controller.api.post('/account/password',{
        'currentPassword':current,'newPassword':next,
      });
      await widget.controller.logout();
      if(mounted) Navigator.pop(context);
    });
  }

  Future<void> _changeEmail() async {
    final email = await _prompt('Cambiar correo','Nuevo correo electrónico',
      description:'Enviaremos un código a tu nuevo correo.');
    if(email == null || email.trim().isEmpty) return;
    final currentPassword = await _prompt('Confirma tu identidad',
      'Contraseña actual',secret:true);
    if(currentPassword == null) return;
    await _action(() async {
      await widget.controller.api.post('/account/email/change-request',{
        'email':email.trim(),'currentPassword':currentPassword,
      });
      if(!mounted) return;
      final code = await _prompt('Verificar nuevo correo','Código de seis dígitos');
      if(code == null) return;
      await widget.controller.api.post('/account/email/confirm',{'code':code.trim()});
      await widget.controller.logout();
      if(mounted) Navigator.pop(context);
    });
  }

  Future<void> _revokeSession(String id) async {
    if(!await _confirm('Cerrar esta sesión',
        'Esta sesión perderá acceso inmediatamente.')) return;
    await _action(() async {
      await widget.controller.api.delete('/account/sessions/$id');
      _message('Sesión revocada');
    });
  }

  Future<void> _invite() async {
    final email = await _prompt('Invitar usuario','Correo de la persona');
    if(email == null || email.isEmpty || !mounted) return;
    String selected = 'VIEWER';
    final role = await showDialog<String>(context:context,
      builder:(ctx)=>StatefulBuilder(builder:(ctx,setDialog)=>AlertDialog(
        backgroundColor:GuardianPalette.surface,
        title:const Text('Seleccionar permisos'),
        content:DropdownButtonFormField<String>(
          value:selected,
          decoration:const InputDecoration(labelText:'Rol'),
          items:roles.map((r)=>DropdownMenuItem(value:r,child:Text(r))).toList(),
          onChanged:(v)=>setDialog(()=>selected=v??'VIEWER')),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),
          ElevatedButton(onPressed:()=>Navigator.pop(ctx,selected),
              child:const Text('Enviar invitación')),
        ],
      )));
    if(role == null) return;
    await _action(() async {
      await widget.controller.api.post('/account/invitations',{'email':email.trim(),'role':role});
      _message('Invitación enviada. El usuario recibirá su código por correo.');
    });
  }

  Future<void> _acceptInvite() async {
    final token = await _prompt('Aceptar invitación','Código recibido por correo');
    if(token == null || token.trim().isEmpty) return;
    await _action(() async {
      await widget.controller.api.post('/account/invitations/accept',{'token':token.trim()});
      _message('Invitación aceptada');
    });
  }

  Future<void> _changeRole(Map<String,dynamic> member) async {
    final role = await showDialog<String>(context:context,builder:(ctx)=>SimpleDialog(
      backgroundColor:GuardianPalette.surface,
      title:const Text('Cambiar permisos'),
      children:roles.map((role)=>SimpleDialogOption(
        onPressed:()=>Navigator.pop(ctx,role),child:Text(role))).toList(),
    ));
    if(role == null) return;
    await _action(() async {
      await widget.controller.api.patch('/account/members/${member['id']}/role',{'role':role});
      _message('Permisos actualizados');
    });
  }

  Future<void> _removeMember(Map<String,dynamic> member) async {
    if(!await _confirm('Revocar usuario',
      'La persona perderá los permisos de este espacio Guardian.')) return;
    await _action(() async {
      await widget.controller.api.delete('/account/members/${member['id']}');
      _message('Acceso revocado');
    });
  }

  Future<void> _deactivate() async {
    if(!await _confirm('Desactivar mi cuenta',
      'Se revocarán sesiones, claves de móviles y agentes. Para reactivar necesitarás '
      'verificar tu correo y volver a vincular tus equipos.')) return;
    final password = await _prompt('Confirmar desactivación','Tu contraseña',secret:true);
    if(password == null) return;
    await _action(() async {
      await widget.controller.api.post('/account/deactivate',{'password':password});
      await widget.controller.logout();
      if(mounted) Navigator.pop(context);
    });
  }

  Future<void> _delete() async {
    if(!await _confirm('Eliminar definitivamente',
      'Se borrarán datos, equipos, eventos, ubicaciones, fotografías y usuarios '
      'autorizados de tu espacio en el servidor. Esta acción no se puede deshacer. '
      'Las copias de seguridad y datos locales requieren su propio ciclo de eliminación.')) return;
    final password = await _prompt('Verificar identidad','Contraseña de la cuenta',secret:true);
    if(password == null) return;
    await _action(() async {
      await widget.controller.api.post('/account/deletion/request',{'password':password});
      if(!mounted) return;
      final code = await _prompt('Eliminación definitiva', 'Código enviado a tu correo');
      if(code == null) return;
      await widget.controller.api.post('/account/deletion/confirm',{'code':code.trim()});
      final accountId = account['id']?.toString() ?? '';
      await widget.controller.logout();
      // Clear locally stored biometric signing material after account erasure.
      await GuardianApi.storage.delete(key:'guardian.mobile.$accountId.seed');
      await GuardianApi.storage.delete(key:'guardian.mobile.$accountId.credential');
      if(mounted) Navigator.pop(context);
    });
  }

  Widget _panel(Widget child) => Card(child:Padding(
    padding:const EdgeInsets.all(19),child:child));
  Widget _option(IconData icon, String title, String subtitle, VoidCallback onTap,
      {Color color=GuardianPalette.teal}) => _panel(ListTile(
    contentPadding:EdgeInsets.zero,
    leading:Icon(icon,color:color), title:Text(title),
    subtitle:Text(subtitle,style:const TextStyle(color:GuardianPalette.muted)),
    trailing:const Icon(Icons.chevron_right,color:GuardianPalette.muted),onTap:onTap,
  ));

  Widget _information()=>Column(children:[
    _panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('INFORMACIÓN PERSONAL',style:TextStyle(
          color:GuardianPalette.teal,fontWeight:FontWeight.bold,letterSpacing:1.2)),
      const SizedBox(height:14),
      Text(account['name']?.toString()??'',style:Theme.of(context).textTheme.titleLarge),
      const SizedBox(height:6),
      Text(account['email']?.toString()??'',style:const TextStyle(color:GuardianPalette.muted)),
      const SizedBox(height:6),
      Text('Teléfono: ${account['phone']??'No definido'}',
          style:const TextStyle(color:GuardianPalette.muted)),
    ])),
    const SizedBox(height:12),
    _option(Icons.person_outline,'Modificar información','Nombre y teléfono',_editProfile),
    const SizedBox(height:12),
    _option(Icons.alternate_email,'Cambiar correo','Requiere verificar el correo nuevo',_changeEmail),
  ]);

  Widget _security()=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    _option(Icons.password,'Cambiar contraseña',
      'Se cerrarán todas las sesiones',_changePassword),
    const SizedBox(height:15),
    const Text('SESIONES ACTIVAS',style:TextStyle(
      color:GuardianPalette.teal,fontWeight:FontWeight.w800,letterSpacing:1.2)),
    const SizedBox(height:10),
    for(final session in sessions) Padding(padding:const EdgeInsets.only(bottom:10),
      child:_panel(Row(children:[
        const Icon(Icons.devices,color:GuardianPalette.blue),
        const SizedBox(width:12),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text((session['clientLabel']??'Sesión').toString()),
          Text(session['current']==true?'Este dispositivo':'Dispositivo vinculado',
            style:const TextStyle(color:GuardianPalette.muted,fontSize:12)),
        ])),
        IconButton(tooltip:'Cerrar sesión',icon:const Icon(Icons.logout,color:GuardianPalette.red),
          onPressed:()=>_revokeSession(session['id'].toString())),
      ]))),
    const SizedBox(height:8),
    OutlinedButton.icon(icon:const Icon(Icons.lock_outline),
      onPressed:()=>_action(() async {
        await widget.controller.api.post('/account/sessions/revoke-others');
        _message('Se cerraron las demás sesiones');
      }),label:const Text('Cerrar otras sesiones')),
  ]);

  Widget _team()=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Wrap(spacing:10,runSpacing:10,children:[
      ElevatedButton.icon(onPressed:_invite,icon:const Icon(Icons.person_add_alt),
        label:const Text('Invitar usuario')),
      OutlinedButton.icon(onPressed:_acceptInvite,icon:const Icon(Icons.mark_email_read_outlined),
        label:const Text('Aceptar invitación')),
    ]),
    const SizedBox(height:17),
    const Text('USUARIOS AUTORIZADOS',style:TextStyle(color:GuardianPalette.teal,
      fontWeight:FontWeight.w800,letterSpacing:1.2)),
    if(members.isEmpty) const Padding(padding:EdgeInsets.symmetric(vertical:18),
      child:Text('Todavía no has invitado a otros usuarios.',
        style:TextStyle(color:GuardianPalette.muted))),
    for(final member in members) Padding(padding:const EdgeInsets.only(top:10),
      child:_panel(Row(children:[
        const Icon(Icons.account_circle,color:GuardianPalette.blue),
        const SizedBox(width:12),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text((member['name']??'Usuario').toString(),
            style:const TextStyle(fontWeight:FontWeight.w800)),
          Text((member['email']??'').toString(),
            style:const TextStyle(color:GuardianPalette.muted,fontSize:11)),
          Text('Rol: ${member['role']}',
            style:const TextStyle(color:GuardianPalette.teal,fontSize:11)),
        ])),
        IconButton(icon:const Icon(Icons.manage_accounts_outlined),
          tooltip:'Cambiar rol',onPressed:()=>_changeRole(member)),
        IconButton(icon:const Icon(Icons.person_remove_outlined,color:GuardianPalette.red),
          tooltip:'Revocar usuario',onPressed:()=>_removeMember(member)),
      ]))),
    const SizedBox(height:20),
    const Text('INVITACIONES',style:TextStyle(color:GuardianPalette.teal,
      fontWeight:FontWeight.w800,letterSpacing:1.2)),
    for(final invite in invitations) Padding(padding:const EdgeInsets.only(top:8),
      child:_panel(Row(children:[
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(invite['email'].toString()),
          Text('${invite['role']} · ${invite['status']}',
            style:const TextStyle(color:GuardianPalette.muted,fontSize:12)),
        ])),
        if(invite['status']=='PENDING') IconButton(
          icon:const Icon(Icons.cancel_outlined,color:GuardianPalette.red),
          tooltip:'Cancelar invitación',
          onPressed:()=>_action(() async {
            await widget.controller.api.delete('/account/invitations/${invite['id']}');
          })),
      ]))),
    const SizedBox(height:15),
    const Text('Roles: VIEWER consulta el espacio, AUTHORIZED está autorizado '
      'a utilizarlo y ADMIN puede modificar políticas. Ningún invitado es '
      'propietario de la cuenta.',
      style:TextStyle(color:GuardianPalette.muted,height:1.5,fontSize:12)),
  ]);

  Widget _privacy()=>Column(children:[
    _option(Icons.pause_circle_outline,'Desactivar temporalmente',
      'Revoca claves y sesiones hasta que reactives por correo',_deactivate,
      color:GuardianPalette.amber),
    const SizedBox(height:14),
    _option(Icons.delete_forever_outlined,'Eliminar mi cuenta',
      'Borrado irreversible tras contraseña y código de correo',_delete,
      color:GuardianPalette.red),
    const SizedBox(height:15),
    const Text('La información biométrica y las capturas guardadas en otros '
      'computadores deben eliminarse también en esos equipos. '
      'Las copias de seguridad siguen su período de retención.',
      style:TextStyle(color:GuardianPalette.muted,fontSize:12,height:1.5)),
  ]);

  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor:GuardianPalette.bg,
    appBar:AppBar(title:const Text('Cuenta y seguridad'),
      backgroundColor:GuardianPalette.surface,
      actions:[IconButton(onPressed:_load,icon:const Icon(Icons.refresh))]),
    body:SafeArea(child:Center(child:ConstrainedBox(
      constraints:const BoxConstraints(maxWidth:850),
      child:ListView(padding:const EdgeInsets.all(20),children:[
        const Text('Gestiona tu identidad Guardian, permisos de usuarios y privacidad.',
          style:TextStyle(color:GuardianPalette.muted)),
        const SizedBox(height:18),
        SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[
          for(final item in <(String,int)>[
            ('Mi información',0),('Seguridad',1),('Usuarios',2),('Privacidad',3)
          ]) Padding(padding:const EdgeInsets.only(right:8),child:ChoiceChip(
            label:Text(item.$1),selected:section==item.$2,
            onSelected:(_)=>setState(()=>section=item.$2))),
        ])),
        const SizedBox(height:20),
        if(loading)const Center(child:CircularProgressIndicator()),
        if(error!=null)Text(error!,style:const TextStyle(color:GuardianPalette.red)),
        if(!loading&&error==null) ...[
          if(section==0)_information(),
          if(section==1)_security(),
          if(section==2)_team(),
          if(section==3)_privacy(),
        ],
        if(saving)const Padding(padding:EdgeInsets.all(15),
          child:Center(child:CircularProgressIndicator())),
      ]),
    ))),
  );
}
