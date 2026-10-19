import 'package:flutter/material.dart';

import '../tokens.dart';

/// PETORA mark: a paw inside a rounded forest-green tile, optional wordmark.
class PetoraLogo extends StatelessWidget {
  const PetoraLogo({super.key, this.size = 36, this.wordmark = true, this.onDark = false});
  final double size;
  final bool wordmark, onDark;

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white : context.cs.onSurface;
    return Semantics(
      label: 'PETORA',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * 0.3),
              gradient: const LinearGradient(
                colors: [PColor.primary500, PColor.primary700],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Icon(Icons.pets, color: Colors.white, size: size * 0.58),
          ),
          if (wordmark) ...[
            SizedBox(width: size * 0.3),
            ExcludeSemantics(
              child: Text(
                'PETORA',
                style: TextStyle(
                  fontFamily: PType.fontFamily,
                  fontSize: size * 0.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: fg,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
