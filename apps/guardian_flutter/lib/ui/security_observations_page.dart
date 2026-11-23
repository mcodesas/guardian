import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:guardian_app/core/guardian_controller.dart';
import 'package:guardian_app/core/guardian_theme.dart';

/// Owner-only private security timeline: last confirmed position may be old.
class SecurityObservationsPage extends StatefulWidget {
  const SecurityObservationsPage({super.key, required this.controller});
  final GuardianController controller;
  @override
  State<SecurityObservationsPage> createState() => _SecurityObservationsPageState();
}

class _SecurityObservationsPageState extends State<SecurityObservationsPage> {
  String? selectedDevice;
  List<Map<String, dynamic>> events = [];
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    if (widget.controller.devices.isNotEmpty) {
      selectedDevice = widget.controller.devices.first['id']?.toString();
      _load();
    }
  }

  Future<void> _load() async {
    final id = selectedDevice;
    if (id == null) return;
    setState(() { loading = true; error = null; });
    try {
      final result = await widget.controller.api.get('/devices/$id/security-observations');
      if (mounted) setState(() {
        events = (result as List).map((v) => Map<String, dynamic>.from(v as Map)).toList();
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _localDate(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    return parsed == null ? 'Fecha desconocida' :
      '${parsed.day.toString().padLeft(2, '0')}/'
      '${parsed.month.toString().padLeft(2, '0')}/'
      '${parsed.year} ${parsed.hour.toString().padLeft(2, '0')}:'
      '${parsed.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _viewPhoto(Map<String, dynamic> event) async {
    final device = selectedDevice;
    if (device == null) return;
    Uint8List? image;
    try {
      // Authenticated request, including Guardian's refresh-token handling.
      final bytes = await widget.controller.api.getBytes(
        '/devices/$device/security-observations/${event['id']}/photo');
      image = Uint8List.fromList(bytes);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La evidencia no está disponible o requiere iniciar sesión.')));
      return;
    }
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: GuardianPalette.surface,
      title: const Text('Fotografía del intento'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 540),
        child: Image.memory(image!, fit: BoxFit.contain, gaplessPlayback: false),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
    ));
  }

  Widget _location(Map<String, dynamic> item) {
    final lat = item['latitude'];
    final lon = item['longitude'];
    if (lat == null || lon == null) {
      return const Text('Ubicación no disponible (sin GPS, permisos o conectividad).',
        style: TextStyle(color: GuardianPalette.muted));
    }
    final observedAt = DateTime.tryParse(item['locationObservedAt']?.toString() ?? '');
    final isOld = observedAt == null || DateTime.now().toUtc().difference(observedAt.toUtc())
        > const Duration(minutes: 30);
    final coords = '$lat, $lon';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.location_on_outlined, color: isOld ? GuardianPalette.amber : GuardianPalette.teal),
        const SizedBox(width: 7),
        Expanded(child: Text(isOld ? 'Última ubicación conocida' : 'Ubicación registrada',
            style: const TextStyle(fontWeight: FontWeight.w800))),
      ]),
      const SizedBox(height: 8),
      SelectableText(coords, style: const TextStyle(color: GuardianPalette.white)),
      const SizedBox(height: 6),
      Text('Medida: ${_localDate(item['locationObservedAt'])} · '
          'precisión aproximada: ${item['accuracyMeters'] ?? '?'} m',
          style: const TextStyle(fontSize: 12, color: GuardianPalette.muted)),
      Text('Fuente: ${item['locationSource'] == 'CACHED' ? 'posición almacenada' : 'Windows'}',
          style: const TextStyle(fontSize: 12, color: GuardianPalette.muted)),
      TextButton.icon(onPressed: () async {
        await Clipboard.setData(ClipboardData(text: coords));
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Coordenadas copiadas')));
      }, icon: const Icon(Icons.copy), label: const Text('Copiar coordenadas')),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GuardianPalette.bg,
      appBar: AppBar(title: const Text('Ubicación y accesos'),
        backgroundColor: GuardianPalette.surface,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Solo se muestran datos comunicados por un dispositivo autorizado. '
              'Una ubicación antigua no representa la posición actual.',
              style: TextStyle(color: GuardianPalette.muted, height: 1.5)),
          const SizedBox(height: 18),
          if (widget.controller.devices.isEmpty)
            const Text('Primero vincula un computador.',
                style: TextStyle(color: GuardianPalette.muted)),
          if (widget.controller.devices.isNotEmpty)
            DropdownButtonFormField<String>(
              value: selectedDevice,
              decoration: const InputDecoration(labelText: 'Computador protegido'),
              items: widget.controller.devices.map((device) => DropdownMenuItem<String>(
                value: device['id']?.toString(),
                child: Text((device['name'] ?? 'Computador').toString()),
              )).toList(),
              onChanged: (value) {
                setState(() { selectedDevice = value; events = []; });
                _load();
              },
            ),
          if (loading) const Padding(padding: EdgeInsets.all(35),
            child: Center(child: CircularProgressIndicator())),
          if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(error!, style: const TextStyle(color: GuardianPalette.red))),
          if (!loading && events.isEmpty && selectedDevice != null)
            const Padding(padding: EdgeInsets.all(20),
              child: Text('Aún no hay posiciones ni accesos fallidos registrados.',
                style: TextStyle(color: GuardianPalette.muted))),
          for (final item in events) Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Card(child: Padding(padding: const EdgeInsets.all(19),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(item['type'] == 'FAILED_UNLOCK'
                      ? Icons.gpp_bad_outlined : Icons.location_history,
                      color: item['type'] == 'FAILED_UNLOCK'
                          ? GuardianPalette.red : GuardianPalette.teal),
                  const SizedBox(width: 9),
                  Expanded(child: Text(item['type'] == 'FAILED_UNLOCK'
                    ? 'Intento fallido de desbloqueo' : 'Ubicación con equipo bloqueado',
                    style: const TextStyle(fontWeight: FontWeight.bold))),
                ]),
                const SizedBox(height: 6),
                Text('Registrado: ${_localDate(item['occurredAt'])}',
                  style: const TextStyle(color: GuardianPalette.muted, fontSize: 12)),
                const SizedBox(height: 15),
                _location(item),
                const SizedBox(height: 12),
                if (item['hasPhoto'] == true) OutlinedButton.icon(
                  onPressed: () => _viewPhoto(item),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Ver foto cifrada del incidente')),
                if (item['hasPhoto'] != true && item['type'] == 'FAILED_UNLOCK')
                  Text('Fotografía: ${item['photoStatus'] ?? 'no disponible'}',
                    style: const TextStyle(color: GuardianPalette.amber, fontSize: 12)),
              ])),
            )),
        ]),
      ))),
    );
  }
}
