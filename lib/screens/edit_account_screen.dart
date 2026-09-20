import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../state/auth_provider.dart';

class EditAccountScreen extends StatefulWidget {
  const EditAccountScreen({super.key});
  @override
  State<EditAccountScreen> createState() => _EditAccountScreenState();
}

const _genderOptions = ['Hombre', 'Mujer', 'No opino'];

class _EditAccountScreenState extends State<EditAccountScreen> {
  static const _labels = {
    'fullName': 'Nombre completo',
    'bio': 'Biografía',
    'city': 'Ciudad actual',
    'pronouns': 'Pronombres',
    'phone': 'Teléfono (para tu tarjeta de fidelización)',
  };
  final _fields = {
    for (final key in _labels.keys) key: TextEditingController()
  };
  final _api = ApiClient();
  bool _busy = true;
  bool _loaded = false;
  String? _error, _avatar, _cover, _gender;
  DateTime? _birthDate;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.get('/users/me/profile');
      if (!mounted) return;
      for (final field in _fields.entries) {
        field.value.text = '${data[field.key] ?? ''}';
      }
      final gender = data['gender'] as String?;
      setState(() {
        _avatar = data['avatarUrl'];
        _cover = data['coverImageUrl'];
        _gender = _genderOptions.contains(gender) ? gender : null;
        _birthDate = DateTime.tryParse('${data['birthDate'] ?? ''}');
        _loaded = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 20),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _image(bool cover) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await ImagePicker().pickImage(
          source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
      if (file == null) return;
      if (await file.length() > 5 * 1024 * 1024)
        throw ApiException(400, 'La imagen debe pesar menos de 5 MB.');
      final data = await _api.uploadMedia(
          cover ? '/upload/image' : '/users/me/avatar',
          'file',
          await file.readAsBytes(),
          file.name,
          file.mimeType ?? 'image/jpeg');
      if (cover)
        await _api.patch('/users/me/profile', {'coverImageUrl': data['url']});
      if (!mounted) return;
      setState(() {
        if (cover) {
          _cover = data['url'];
        } else {
          _avatar = data['avatarUrl'];
        }
      });
      await context.read<AuthProvider>().refreshProfile();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final values = {
      for (final f in _fields.entries) f.key: f.value.text.trim()
    };
    if (values['fullName']!.isEmpty) {
      setState(() => _error = 'Ingresa tu nombre.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.patch('/users/me/profile', {
        ...values,
        'gender': _gender,
        'birthDate': _birthDate?.toIso8601String().substring(0, 10),
      });
      if (!mounted) return;
      await context.read<AuthProvider>().refreshProfile();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Editar perfil')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        if (_busy) const LinearProgressIndicator(),
        if (_cover != null)
          Image.network(_cover!, height: 140, fit: BoxFit.cover),
        if (_avatar != null)
          CircleAvatar(radius: 40, backgroundImage: NetworkImage(_avatar!)),
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy || !_loaded ? null : () => _image(false),
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Cambiar foto'),
              ),
              OutlinedButton.icon(
                onPressed: _busy || !_loaded ? null : () => _image(true),
                icon: const Icon(Icons.image_outlined, size: 18),
                label: const Text('Cambiar portada'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final field in _fields.entries)
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                  controller: field.value,
                  enabled: !_busy && _loaded,
                  keyboardType: field.key == 'phone'
                      ? TextInputType.phone
                      : TextInputType.text,
                  maxLines: field.key == 'bio' ? 3 : 1,
                  maxLength: field.key == 'bio'
                      ? 500
                      : field.key == 'pronouns'
                          ? 50
                          : 100,
                  decoration: InputDecoration(labelText: _labels[field.key]))),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            initialValue: _gender,
            decoration: const InputDecoration(labelText: 'Género'),
            items: [
              for (final g in _genderOptions)
                DropdownMenuItem(value: g, child: Text(g)),
            ],
            onChanged:
                _busy || !_loaded ? null : (v) => setState(() => _gender = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onTap: _busy || !_loaded ? null : _pickBirthDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                  labelText: 'Fecha de nacimiento',
                  suffixIcon: Icon(Icons.calendar_today_outlined)),
              child: Text(_birthDate == null
                  ? ''
                  : '${_birthDate!.day.toString().padLeft(2, '0')}/${_birthDate!.month.toString().padLeft(2, '0')}/${_birthDate!.year}'),
            ),
          ),
        ),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        if (!_loaded && !_busy)
          TextButton(onPressed: _load, child: const Text('Reintentar')),
        FilledButton(
            onPressed: _busy || !_loaded ? null : _save,
            child: const Text('Guardar cambios')),
      ]));
}
