enum CapturedMediaType { image, video }

class CapturedMedia {
  const CapturedMedia({required this.path, required this.type});

  final String path;
  final CapturedMediaType type;
}
