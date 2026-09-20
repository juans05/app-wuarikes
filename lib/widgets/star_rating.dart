import 'package:flutter/material.dart';

class StarRating extends StatelessWidget {
  final int value;
  final ValueChanged<int>? onChanged;
  final double size;

  const StarRating({super.key, required this.value, this.onChanged, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final starIndex = i + 1;
        return IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: onChanged == null ? null : () => onChanged!(starIndex),
          icon: Icon(
            starIndex <= value ? Icons.star_rounded : Icons.star_border_rounded,
            color: Colors.amber,
            size: size,
          ),
        );
      }),
    );
  }
}
