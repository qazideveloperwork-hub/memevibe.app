/// Builds a single [ColorFilter.matrix]-compatible 4x5 matrix combining
/// saturation, contrast, and brightness. Composed analytically (rather than
/// stacking three separate ColorFiltered widgets) so it's one GPU pass.
///
/// - [brightness]: -1..1, 0 is neutral.
/// - [contrast]: 0..2, 1 is neutral.
/// - [saturation]: 0..2, 1 is neutral (0 = grayscale).
List<double> buildAdjustmentMatrix({
  double brightness = 0,
  double contrast = 1,
  double saturation = 1,
}) {
  const lumR = 0.2126, lumG = 0.7152, lumB = 0.0722;
  final invSat = 1 - saturation;

  final satR = [invSat * lumR + saturation, invSat * lumG, invSat * lumB];
  final satG = [invSat * lumR, invSat * lumG + saturation, invSat * lumB];
  final satB = [invSat * lumR, invSat * lumG, invSat * lumB + saturation];

  final translate = 128 * (1 - contrast) + brightness * 255;

  return [
    contrast * satR[0],
    contrast * satR[1],
    contrast * satR[2],
    0,
    translate,
    contrast * satG[0],
    contrast * satG[1],
    contrast * satG[2],
    0,
    translate,
    contrast * satB[0],
    contrast * satB[1],
    contrast * satB[2],
    0,
    translate,
    0,
    0,
    0,
    1,
    0,
  ];
}
