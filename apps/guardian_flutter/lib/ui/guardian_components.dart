import 'package:flutter/material.dart';
import 'package:guardian_app/core/guardian_theme.dart';

class GuardianLogo extends StatelessWidget {
  const GuardianLogo({super.key, this.size=54});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width:size, height:size,
    decoration:BoxDecoration(
      gradient:const LinearGradient(
        colors:[GuardianPalette.teal,GuardianPalette.blue],
        begin:Alignment.topLeft,end:Alignment.bottomRight),
      borderRadius:BorderRadius.circular(size*.30),
      boxShadow:[BoxShadow(color:GuardianPalette.teal.withValues(alpha:.16),
        blurRadius:22,spreadRadius:1)],
    ),
    child:Icon(Icons.shield_rounded,color:GuardianPalette.bg,size:size*.6),
  );
}

class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding=const EdgeInsets.all(20)});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding:padding,
    decoration:BoxDecoration(
      color:GuardianPalette.surface,
      borderRadius:BorderRadius.circular(23),
      border:Border.all(color:GuardianPalette.line,width:.8),
    ),
    child:child,
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key,this.subtitle,this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(children:[
    Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(title,style:Theme.of(context).textTheme.titleLarge),
      if(subtitle!=null) ...[
        const SizedBox(height:4),
        Text(subtitle!,style:const TextStyle(color:GuardianPalette.muted,fontSize:12)),
      ],
    ])),
    if(trailing!=null) trailing!,
  ]);
}

class StatusTag extends StatelessWidget {
  const StatusTag(this.text, this.color, {super.key,this.icon});
  final String text;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context)=>Container(
    padding:const EdgeInsets.symmetric(horizontal:12,vertical:7),
    decoration:BoxDecoration(
      color:color.withValues(alpha:.11),borderRadius:BorderRadius.circular(99),
      border:Border.all(color:color.withValues(alpha:.25)),
    ),
    child:Row(mainAxisSize:MainAxisSize.min,children:[
      if(icon!=null) ...[Icon(icon,size:13,color:color),const SizedBox(width:5)],
      Text(text,style:TextStyle(color:color,fontSize:11,fontWeight:FontWeight.w700)),
    ]),
  );
}

void guardianMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
}

String friendlyTime(dynamic raw) {
  final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  if(date==null) return 'Sin fecha';
  final day = date.day.toString().padLeft(2,'0');
  final month = date.month.toString().padLeft(2,'0');
  final hr = date.hour.toString().padLeft(2,'0');
  final minute = date.minute.toString().padLeft(2,'0');
  return '$day/$month  $hr:$minute';
}

class GuardianEmpty extends StatelessWidget {
  const GuardianEmpty({super.key,required this.title,required this.description,
    this.icon=Icons.inbox_outlined});
  final IconData icon;
  final String title;
  final String description;
  @override
  Widget build(BuildContext context)=>GlassCard(child:Padding(
    padding:const EdgeInsets.symmetric(vertical:42,horizontal:12),
    child:Column(children:[
      Container(width:72,height:72,decoration:BoxDecoration(
        color:GuardianPalette.elevated,borderRadius:BorderRadius.circular(22)),
        child:Icon(icon,color:GuardianPalette.teal,size:36)),
      const SizedBox(height:20),
      Text(title,style:Theme.of(context).textTheme.titleLarge,textAlign:TextAlign.center),
      const SizedBox(height:8),
      Text(description,style:const TextStyle(color:GuardianPalette.muted),
        textAlign:TextAlign.center),
    ]),
  ));
}
