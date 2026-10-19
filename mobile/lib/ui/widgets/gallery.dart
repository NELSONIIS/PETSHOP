import 'package:flutter/material.dart';

import '../../models/listing.dart';
import '../tokens.dart';
import 'net_image.dart';

/// Swipeable gallery with a page counter; tapping opens [FullScreenGallery].
class ImageGallery extends StatefulWidget {
  const ImageGallery({super.key, required this.images, this.iconSlug, this.aspectRatio = 4 / 3, this.heroTag});
  final List<Img> images;
  final String? iconSlug;
  final double aspectRatio;
  final String? heroTag;

  @override
  State<ImageGallery> createState() => _ImageGalleryState();
}

class _ImageGalleryState extends State<ImageGallery> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: PNetImage(null, iconSlug: widget.iconSlug),
      );
    }
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _i = i),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) => FullScreenGallery(images: widget.images, initial: i),
                ),
              ),
              child: Semantics(
                image: true,
                label: widget.images[i].altText.isNotEmpty
                    ? widget.images[i].altText
                    : 'Photo ${i + 1} of ${widget.images.length}',
                child: PNetImage(widget.images[i].best, memCacheWidth: 1000),
              ),
            ),
          ),
          if (widget.images.length > 1) ...[
            Positioned(
              right: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  '${_i + 1}/${widget.images.length}',
                  style: context.tt.labelSmall?.copyWith(color: Colors.white),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < widget.images.length && i < 10; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      width: i == _i ? 14 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _i ? Colors.white : Colors.white54,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class FullScreenGallery extends StatefulWidget {
  const FullScreenGallery({super.key, required this.images, this.initial = 0});
  final List<Img> images;
  final int initial;
  @override
  State<FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<FullScreenGallery> {
  late final PageController _pc = PageController(initialPage: widget.initial);
  late int _i = widget.initial;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_i + 1} of ${widget.images.length}'),
      ),
      body: PageView.builder(
        controller: _pc,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _i = i),
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(child: PNetImage(widget.images[i].full, fit: BoxFit.contain, memCacheWidth: 1600)),
        ),
      ),
    );
  }
}
