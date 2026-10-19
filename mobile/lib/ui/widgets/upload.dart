import 'package:flutter/material.dart';

import '../../models/listing.dart';
import '../tokens.dart';
import 'net_image.dart';

enum UploadStatus { queued, uploading, done, failed }

/// One tile per photo in the listing wizard: shows progress, failure with Retry, and cancel/delete.
class UploadTile extends StatelessWidget {
  const UploadTile({
    super.key,
    this.image,
    this.localPath,
    this.status = UploadStatus.done,
    this.progress = 0,
    this.isCover = false,
    this.onRetry,
    this.onCancel,
    this.onMakeCover,
    this.onDelete,
    this.error,
    this.index,
  });
  final Img? image;
  final String? localPath;
  final UploadStatus status;
  final double progress;
  final bool isCover;
  final VoidCallback? onRetry, onCancel, onMakeCover, onDelete;
  final String? error;
  final int? index;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Photo ${index == null ? '' : index! + 1} ${isCover ? 'cover ' : ''}${status.name}',
      child: ClipRRect(
        borderRadius: PRadius.cardR,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (image != null && !image!.isEmpty)
              PNetImage(image!.small, memCacheWidth: 300)
            else
              Container(
                color: context.cs.surfaceContainerHighest,
                child: Icon(Icons.image_outlined, color: context.pc.textMuted),
              ),
            if (status == UploadStatus.uploading || status == UploadStatus.queued)
              Container(
                color: Colors.black54,
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        value: status == UploadStatus.queued || progress == 0 ? null : progress,
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      status == UploadStatus.queued ? 'Waiting' : '${(progress * 100).round()}%',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ],
                ),
              ),
            if (status == UploadStatus.failed)
              Container(
                color: const Color(0xA8000000),
                padding: const EdgeInsets.all(4),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white, size: 20),
                    Text(
                      error ?? 'Failed',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                    TextButton(
                      onPressed: onRetry,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 32),
                        padding: EdgeInsets.zero,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            if (status == UploadStatus.done && isCover)
              Positioned(
                left: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: context.cs.primary, borderRadius: BorderRadius.circular(6)),
                  child: Text('Cover', style: context.tt.labelSmall?.copyWith(color: context.cs.onPrimary)),
                ),
              ),
            Positioned(
              right: 0,
              top: 0,
              child: Row(
                children: [
                  if (status == UploadStatus.done && !isCover && onMakeCover != null)
                    _MiniButton(icon: Icons.star_outline, tooltip: 'Make cover photo', onTap: onMakeCover!),
                  if (status == UploadStatus.uploading && onCancel != null)
                    _MiniButton(icon: Icons.close, tooltip: 'Cancel upload', onTap: onCancel!),
                  if ((status == UploadStatus.done || status == UploadStatus.failed) && onDelete != null)
                    _MiniButton(icon: Icons.delete_outline, tooltip: 'Remove photo', onTap: onDelete!),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onTap,
    icon: Icon(icon, size: 18, color: Colors.white),
    style: IconButton.styleFrom(
      backgroundColor: Colors.black54,
      minimumSize: const Size(40, 40),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.padded,
    ),
  );
}
