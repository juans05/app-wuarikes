import 'package:flutter/material.dart';
import '../core/api_client.dart';

class InfoSuggestionDialog extends StatefulWidget {
  final String placeId;
  const InfoSuggestionDialog({super.key, required this.placeId});
  @override
  State<InfoSuggestionDialog> createState() => _InfoSuggestionDialogState();
}

class _InfoSuggestionDialogState extends State<InfoSuggestionDialog> {
  static const _fields = {
    'phone': 'Teléfono',
    'address': 'Dirección',
    'menu': 'Carta y precios',
    'hours': 'Horarios',
    'name': 'Nombre',
    'website': 'Sitio web',
    'category': 'Categoría',
    'amenities': 'Servicios'
  };
  String _field = 'phone';
  final _value = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_field != 'menu' && _value.text.trim().isEmpty) {
      setState(() => _error = 'Indica cuál es la información correcta.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient().post('/checkins/info-suggestions', {
        'placeId': widget.placeId,
        'field': _field,
        if (_field != 'menu') 'suggestedValue': _value.text.trim()
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Reportar información desactualizada'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
                'Tu sugerencia se enviará a la comunidad para su validación.'),
            DropdownButton<String>(
                isExpanded: true,
                value: _field,
                items: [
                  for (final f in _fields.entries)
                    DropdownMenuItem(value: f.key, child: Text(f.value))
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(() {
                          _field = v!;
                          _value.clear();
                        })),
            if (_field != 'menu')
              TextField(
                  controller: _value,
                  maxLength: 500,
                  decoration:
                      const InputDecoration(labelText: 'Información correcta')),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
          ])),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: _busy ? null : _submit,
                child: const Text('Enviar sugerencia'))
          ]);
}
