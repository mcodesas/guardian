import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:guardian_app/core/guardian_controller.dart';
import 'package:guardian_app/core/guardian_theme.dart';
import 'package:guardian_app/ui/guardian_components.dart';

enum AuthMode { login, register, verify }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.controller});
  final GuardianController controller;
  @override State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  final code = TextEditingController();
  final server = TextEditingController();
  AuthMode mode = AuthMode.login;
  bool hidden = true, saving = false;

  @override void initState() {
    super.initState();
    server.text = widget.controller.api.serverUrl;
  }
  @override void dispose() {
    email.dispose(); password.dispose(); name.dispose();
    code.dispose(); server.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!(form.currentState?.validate() ?? false)) return;
    setState(()=>saving=true);
    try {
      if(widget.controller.api.serverUrl.isEmpty) {
        throw StateError('Configura la URL segura del servidor primero.');
      }
      if(mode==AuthMode.login) {
        await widget.controller.login(email.text.trim(),password.text);
      } else if(mode==AuthMode.register) {
        await widget.controller.register(name.text,email.text.trim(),password.text);
        if(mounted) setState(()=>mode=AuthMode.verify);
      } else {
        await widget.controller.verify(email.text.trim(),code.text.trim());
        if(mounted) {
          setState(()=>mode=AuthMode.login);
          guardianMessage(context,'Correo verificado. Ya puedes iniciar sesión.');
        }
      }
    } catch(e) {
      if(mounted) guardianMessage(context,e.toString().replaceFirst('Bad state: ',''));
    } finally {
      if(mounted) setState(()=>saving=false);
    }
  }

  Future<void> configureServer() async {
    server.text=widget.controller.api.serverUrl;
    final result=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
      backgroundColor:GuardianPalette.surface,
      title:const Text('Conectar con Guardian'),
      content:ConstrainedBox(constraints:const BoxConstraints(maxWidth:420),
        child:Column(mainAxisSize:MainAxisSize.min,
          crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('Introduce el dominio HTTPS de tu API.',
            style:TextStyle(color:GuardianPalette.muted)),
          const SizedBox(height:16),
          TextField(controller:server,keyboardType:TextInputType.url,
            autocorrect:false,
            decoration:const InputDecoration(labelText:'URL del servidor',
              hintText:'https://seguridad.tudominio.com')),
          const SizedBox(height:8),
          const Text('HTTP solo está permitido en desarrollo local.',
            style:TextStyle(color:GuardianPalette.muted,fontSize:11)),
        ])),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),
        ElevatedButton(onPressed:()=>Navigator.pop(ctx,server.text),child:const Text('Guardar')),
      ],
    ));
    if(result==null) return;
    try {
      await widget.controller.setServer(result);
      if(mounted) guardianMessage(context,'Servidor configurado.');
    } catch(e) {
      if(mounted) guardianMessage(context,'No se pudo guardar: $e');
    }
  }

  Future<void> recoverPassword() async {
    final resetEmail=TextEditingController(text:email.text.trim());
    final resetCode=TextEditingController();
    final newPassword=TextEditingController();
    var sent=false;
    final result=await showDialog<bool>(context:context,
      builder:(ctx)=>StatefulBuilder(builder:(ctx,refresh)=>AlertDialog(
      backgroundColor:GuardianPalette.surface,
      title:const Text('Recupera tu acceso'),
      content:ConstrainedBox(constraints:const BoxConstraints(maxWidth:410),
        child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
          const Text('Solicita un código temporal al correo de tu cuenta.',
            style:TextStyle(color:GuardianPalette.muted)),
          const SizedBox(height:15),
          TextField(controller:resetEmail,keyboardType:TextInputType.emailAddress,
            decoration:const InputDecoration(labelText:'Correo electrónico')),
          if(sent)...[
            const SizedBox(height:12),
            TextField(controller:resetCode,keyboardType:TextInputType.number,
              maxLength:6,decoration:const InputDecoration(
                labelText:'Código de seis dígitos',counterText:'')),
            const SizedBox(height:12),
            TextField(controller:newPassword,obscureText:true,
              decoration:const InputDecoration(
                labelText:'Nueva contraseña (mínimo 12 caracteres)')),
          ],
        ]))),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx,false),
          child:const Text('Cancelar')),
        ElevatedButton(onPressed:()async{
          try {
            if(!sent) {
              await widget.controller.requestReset(resetEmail.text.trim());
              refresh(()=>sent=true);
            } else {
              await widget.controller.resetPassword(resetEmail.text.trim(),
                resetCode.text.trim(),newPassword.text);
              if(ctx.mounted) Navigator.pop(ctx,true);
            }
          } catch(e) {
            if(ctx.mounted) guardianMessage(ctx,e.toString());
          }
        },child:Text(sent?'Cambiar contraseña':'Enviar código')),
      ],
    )));
    resetEmail.dispose(); resetCode.dispose(); newPassword.dispose();
    if(result==true && mounted)
      guardianMessage(context,'Contraseña actualizada. Inicia sesión de nuevo.');
  }

  Future<void> reactivateAccount() async {
    if(widget.controller.api.serverUrl.isEmpty) {
      guardianMessage(context,'Configura primero el servidor Guardian');
      return;
    }
    final targetEmail=await showDialog<String>(context:context,builder:(ctx){
      final field=TextEditingController(text:email.text.trim());
      return AlertDialog(backgroundColor:GuardianPalette.surface,
        title:const Text('Reactivar cuenta'),
        content:TextField(controller:field,
          decoration:const InputDecoration(labelText:'Correo de la cuenta')),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),
          ElevatedButton(onPressed:()=>Navigator.pop(ctx,field.text.trim()),
            child:const Text('Enviar código')),
        ]);
    });
    if(targetEmail==null||targetEmail.isEmpty)return;
    try {
      await widget.controller.api.post('/account/reactivate/request',{'email':targetEmail});
      if(!mounted)return;
      final codeInput=TextEditingController();
      final otp=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
        backgroundColor:GuardianPalette.surface,
        title:const Text('Verificación de reactivación'),
        content:TextField(controller:codeInput,keyboardType:TextInputType.number,
          maxLength:6,decoration:const InputDecoration(labelText:'Código recibido')),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),
          ElevatedButton(onPressed:()=>Navigator.pop(ctx,codeInput.text.trim()),
            child:const Text('Reactivar')),
        ]));
      codeInput.dispose();
      if(otp==null)return;
      await widget.controller.api.post('/account/reactivate/confirm',
        {'email':targetEmail,'code':otp});
      if(mounted) guardianMessage(context,'Cuenta reactivada. Vuelve a iniciar sesión.');
    } catch(e) {if(mounted)guardianMessage(context,'No fue posible reactivar: $e');}
  }

  String? validateEmail(String? input) {
    if(!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(input?.trim() ?? '')) {
      return 'Introduce un correo válido';
    }
    return null;
  }

  @override Widget build(BuildContext context) {
    final viewport=MediaQuery.sizeOf(context).width;
    final wide=viewport>=950;
    final paneWidth=wide ? viewport/2 : viewport;
    final formWidth=math.max(0.0,math.min(440.0,paneWidth-48));
    return Scaffold(body:SafeArea(child:Row(children:[
      if(wide) Expanded(child:_brandSide()),
      Expanded(child:Center(child:SingleChildScrollView(
        padding:const EdgeInsets.symmetric(horizontal:24,vertical:28),
        child:SizedBox(width:formWidth,
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          if(!wide) ...[
            const GuardianLogo(),const SizedBox(height:20),
            const Text('GUARDIAN',style:TextStyle(
              color:GuardianPalette.teal,fontWeight:FontWeight.w900,
              letterSpacing:4,fontSize:18)),
            const SizedBox(height:30),
          ],
          const StatusTag('GUARDIAN ID',GuardianPalette.teal,
            icon:Icons.verified_user_outlined),
          const SizedBox(height:18),
          Text(mode==AuthMode.login ? 'Bienvenido de nuevo'
             :mode==AuthMode.register ? 'Crea tu espacio seguro'
             :'Verifica tu correo',
             style:Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height:10),
          Text(mode==AuthMode.login ? 'Todo lo que proteges, desde un solo lugar.'
             :mode==AuthMode.register
             ? 'Empieza a proteger tus dispositivos con una única cuenta.'
             : 'Introduce el código de seis dígitos enviado a tu correo.',
             style:const TextStyle(color:GuardianPalette.muted,height:1.5)),
          const SizedBox(height:32),
          Form(key:form,child:Column(children:[
            if(mode==AuthMode.register) ...[
              TextFormField(controller:name,
                decoration:const InputDecoration(
                  prefixIcon:Icon(Icons.person_outline),labelText:'Nombre'),
                validator:(v)=>(v==null||v.trim().isEmpty)?'Introduce tu nombre':null),
              const SizedBox(height:15),
            ],
            TextFormField(controller:email,enabled:mode!=AuthMode.verify,
              keyboardType:TextInputType.emailAddress,autocorrect:false,
              decoration:const InputDecoration(
                prefixIcon:Icon(Icons.alternate_email_rounded),
                labelText:'Correo electrónico'),
              validator:validateEmail),
            const SizedBox(height:15),
            if(mode==AuthMode.verify) TextFormField(controller:code,
              keyboardType:TextInputType.number,maxLength:6,
              decoration:const InputDecoration(
                prefixIcon:Icon(Icons.password),labelText:'Código de verificación',
                counterText:''),
              validator:(v)=>v?.length==6?null:'Introduce los seis dígitos'),
            if(mode!=AuthMode.verify) TextFormField(
              controller:password,obscureText:hidden,
              enableSuggestions:false,autocorrect:false,
              decoration:InputDecoration(
                prefixIcon:const Icon(Icons.lock_outline),labelText:'Contraseña',
                suffixIcon:IconButton(
                  tooltip:hidden?'Mostrar contraseña':'Ocultar contraseña',
                  onPressed:()=>setState(()=>hidden=!hidden),
                  icon:Icon(hidden?Icons.visibility_outlined:Icons.visibility_off_outlined))),
              validator:(v)=>v==null||v.length<(mode==AuthMode.register?12:1)
                ?'Contraseña demasiado corta':null),
            const SizedBox(height:22),
            SizedBox(width:double.infinity,child:ElevatedButton.icon(
              onPressed:saving?null:submit,
              icon:saving?const SizedBox(width:17,height:17,
                child:CircularProgressIndicator(strokeWidth:2))
                :Icon(mode==AuthMode.verify?Icons.mark_email_read_outlined:
                  Icons.arrow_forward_rounded),
              label:Text(mode==AuthMode.login?'Iniciar sesión'
                :mode==AuthMode.register?'Crear cuenta':'Verificar correo'))),
          ])),
          const SizedBox(height:14),
          if(mode==AuthMode.login)
            Align(alignment:Alignment.centerRight,
              child:TextButton(onPressed:recoverPassword,
                child:const Text('¿Olvidaste tu contraseña?'))),
          if(mode==AuthMode.login)
            Align(alignment:Alignment.centerRight,child:TextButton(
              onPressed:reactivateAccount,child:const Text('Reactivar cuenta'))),
          if(mode==AuthMode.verify)
            Align(alignment:Alignment.centerRight,
              child:TextButton(onPressed:()async{
                try {
                  await widget.controller.resend(email.text.trim());
                  if(mounted) guardianMessage(context,'Si es posible, se envió un nuevo código.');
                } catch(e) {
                  if(mounted) guardianMessage(context,e.toString());
                }
              },child:const Text('Reenviar código'))),
          const SizedBox(height:18),
          Wrap(alignment:WrapAlignment.center,
            crossAxisAlignment:WrapCrossAlignment.center,
            spacing:4,children:[
            Text(mode==AuthMode.login?'¿No tienes cuenta?':'¿Ya tienes cuenta?',
              style:const TextStyle(color:GuardianPalette.muted)),
            TextButton(onPressed:()=>setState(() {
              form.currentState?.reset();
              mode=mode==AuthMode.login?AuthMode.register:AuthMode.login;
            }),child:Text(mode==AuthMode.login?'Regístrate':'Inicia sesión')),
          ]),
          const SizedBox(height:16),
          const Divider(),
          const SizedBox(height:12),
          InkWell(onTap:configureServer,borderRadius:BorderRadius.circular(14),
            child:Padding(padding:const EdgeInsets.symmetric(vertical:9),
              child:Row(children:[
                const Icon(Icons.dns_outlined,color:GuardianPalette.muted,size:20),
                const SizedBox(width:11),
                Expanded(child:Text(widget.controller.api.serverUrl.isEmpty
                    ?'Configurar servidor':widget.controller.api.serverUrl,
                  overflow:TextOverflow.ellipsis,
                  style:const TextStyle(color:GuardianPalette.muted,fontSize:12))),
                const Icon(Icons.settings_outlined,color:GuardianPalette.teal,size:19),
              ]))),
          const SizedBox(height:20),
          const Text('Guardian by MCode · Privacidad por diseño',
            style:TextStyle(color:GuardianPalette.muted,fontSize:11)),
        ])))),
      ),
    ])));
  }

  Widget _brandSide() => Container(
    decoration:const BoxDecoration(gradient:LinearGradient(
      colors:[Color(0xFF101E30),Color(0xFF09252E),Color(0xFF091322)],
      begin:Alignment.topLeft,end:Alignment.bottomRight)),
    child:Stack(children:[
      Positioned(right:-140,top:-130,child:Container(width:440,height:440,
        decoration:BoxDecoration(shape:BoxShape.circle,
          border:Border.all(color:GuardianPalette.teal.withValues(alpha:.14),width:55)))),
      Padding(padding:const EdgeInsets.symmetric(horizontal:34,vertical:36),child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Wrap(crossAxisAlignment:WrapCrossAlignment.center,spacing:15,
            runSpacing:8,children:[
            GuardianLogo(size:52),
            Text('GUARDIAN',style:TextStyle(color:GuardianPalette.white,
              fontSize:22,fontWeight:FontWeight.w900,letterSpacing:3.4)),
          ]),
          const Spacer(),
          const Icon(Icons.security_rounded,size:82,color:GuardianPalette.teal),
          const SizedBox(height:25),
          const Text('Tu mundo,\nbajo protección.',style:TextStyle(
            fontSize:46,color:GuardianPalette.white,
            fontWeight:FontWeight.w900,height:1.12,letterSpacing:-1.7)),
          const SizedBox(height:22),
          const Text('Reconocimiento inteligente, bloqueo preventivo y '
            'autorizaciones seguras desde tu teléfono.',
            style:TextStyle(color:GuardianPalette.muted,fontSize:17,height:1.55)),
          const SizedBox(height:36),
          const Wrap(crossAxisAlignment:WrapCrossAlignment.center,
            spacing:10,runSpacing:8,children:[
            Icon(Icons.check_circle,color:GuardianPalette.teal,size:18),
            Text('Tu identidad. Tus dispositivos. Tus reglas.',
              style:TextStyle(color:GuardianPalette.white)),
          ]),
          const Spacer(),
          const Text('Una solución de MCode SAS',
            style:TextStyle(color:GuardianPalette.muted,fontSize:12)),
        ]),
      ),
    ]),
  );
}
