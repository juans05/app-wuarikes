import 'package:flutter/material.dart';

class AsyncSection extends StatefulWidget {
  final String title;
  final Future<dynamic> Function() load;
  final Widget Function(dynamic) builder;
  const AsyncSection(
      {super.key,
      required this.title,
      required this.load,
      required this.builder});
  @override
  State<AsyncSection> createState() => _AsyncSectionState();
}

class _AsyncSectionState extends State<AsyncSection> {
  late Future<dynamic> _future = widget.load();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          FutureBuilder<dynamic>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done)
                  return const LinearProgressIndicator();
                if (snapshot.hasError)
                  return TextButton.icon(
                      onPressed: () => setState(() => _future = widget.load()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('No se pudo cargar. Reintentar'));
                return widget.builder(snapshot.data);
              }),
        ]),
      );
}
