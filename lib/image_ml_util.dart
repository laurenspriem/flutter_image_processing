import "dart:async";
import "dart:developer" show log;
import "dart:math" show exp, max, pi;
import "dart:typed_data" show Float32List, Uint8List, ByteData;
import "dart:ui";

import 'package:flutter/painting.dart' as paint show decodeImageFromList;

/// These are 8 bit unsigned integers in range 0-255
typedef RGB = (int, int, int);

Future<(Image, ByteData)> _decodeImage(Uint8List imageData) async {
  final Image image = await paint.decodeImageFromList(imageData);
  final ByteData? imageByteData = await image.toByteData();
  return (image, imageByteData!);
}

Future<(Image, Uint8List)> _decodeImageInt8Bytes(Uint8List imageData) async {
  final Image image = await paint.decodeImageFromList(imageData);
  final ByteData? imageByteData = await image.toByteData();
  return (image, imageByteData!.buffer.asUint8List());
}

Future<Uint8List> _encodeData(Uint8List rawRgbData, width, height) async {
  final ImageDescriptor descriptor = ImageDescriptor.raw(
    await ImmutableBuffer.fromUint8List(rawRgbData),
    width: width,
    height: height,
    pixelFormat: PixelFormat.rgba8888,
  );
  final Codec codec = await descriptor.instantiateCodec();
  final FrameInfo frameInfo = await codec.getNextFrame();
  final Image image = frameInfo.image;
  final ByteData? pngBytes =
      await image.toByteData(format: ImageByteFormat.png);
  return pngBytes!.buffer.asUint8List();
}

List<List<double>> create2DGaussianKernel(int size, double sigma) {
  List<List<double>> kernel =
      List.generate(size, (_) => List<double>.filled(size, 0));
  double sum = 0.0;
  int center = size ~/ 2;

  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      int dx = x - center;
      int dy = y - center;
      double g = (1 / (2 * pi * sigma * sigma)) *
          exp(-(dx * dx + dy * dy) / (2 * sigma * sigma));
      kernel[y][x] = g;
      sum += g;
    }
  }

  // Normalize the kernel
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      kernel[y][x] /= sum;
    }
  }

  return kernel;
}

Future<Uint8List> processDownscaleImage(Uint8List imageData) async {
  final startTime = DateTime.now();
  // decode image
  final (image, imgByteData) = await _decodeImage(imageData);
  final decodeTime = DateTime.now();
  final decodeMs = decodeTime.difference(startTime).inMilliseconds;

  // process image
  const int requiredWidth = 256;
  const int requiredHeight = 256;
  const int requiredSize = 4 * requiredWidth * requiredHeight;
  final scale = max(requiredWidth / image.width, requiredHeight / image.height);
  final scaledWidth = (image.width * scale).round();
  final scaledHeight = (image.height * scale).round();
  final widthOffset = max(0, scaledWidth - requiredWidth) / 2;
  final heightOffset = max(0, scaledHeight - requiredHeight) / 2;

  final processedBytes = Uint8List(requiredSize);
  int pixelIndex = 0;
  for (var h = 0 + heightOffset; h < scaledHeight - heightOffset; h++) {
    for (var w = 0 + widthOffset; w < scaledWidth - widthOffset; w++) {
      final Color pixel = _getPixelBilinear(
        w / scale,
        h / scale,
        image,
        imgByteData,
      );
      processedBytes[pixelIndex] = pixel.red;
      processedBytes[pixelIndex + 1] = pixel.green;
      processedBytes[pixelIndex + 2] = pixel.blue;
      processedBytes[pixelIndex + 3] = 255;
      pixelIndex += 4;
    }
  }
  final processTime = DateTime.now();
  final processMs = processTime.difference(decodeTime).inMilliseconds;

  // encode image
  final encoded =
      await _encodeData(processedBytes, requiredWidth, requiredHeight);
  final encodeTime = DateTime.now();
  final encodeMs = encodeTime.difference(processTime).inMilliseconds;
  final totalMs = encodeTime.difference(startTime).inMilliseconds;
  log("Time for regular downscale: total=$totalMs ms, process=$processMs ms, decode=$decodeMs ms, encode=$encodeMs ms");
  return encoded;
}

Future<Uint8List> processBlurImage(Uint8List imageData, double sigma) async {
  // decode image
  final (image, imgByteData) = await _decodeImage(imageData);

  // process image
  final int requiredWidth = image.width;
  final int requiredHeight = image.height;
  final int requiredSize = 4 * requiredWidth * requiredHeight;

  // Create Gaussian kernel
  const int kernelSize = 5;
  const int kernelRadius = kernelSize ~/ 2;
  final List<List<double>> kernel = create2DGaussianKernel(kernelSize, sigma);

  final processedBytes = Uint8List(requiredSize);
  int pixelIndex = 0;
  for (var h = 0; h < requiredHeight; h++) {
    for (var w = 0; w < requiredWidth; w++) {
      final Color pixel = _getPixelGaussianBlur(
        image,
        imgByteData,
        w,
        h,
        kernel,
        kernelSize,
        kernelRadius,
      );
      processedBytes[pixelIndex] = pixel.red;
      processedBytes[pixelIndex + 1] = pixel.green;
      processedBytes[pixelIndex + 2] = pixel.blue;
      processedBytes[pixelIndex + 3] = 255;
      pixelIndex += 4;
    }
  }

  // encode image
  final encoded =
      await _encodeData(processedBytes, requiredWidth, requiredHeight);
  return encoded;
}

Future<Uint8List> processDownscaleImageWithAntialias(
    Uint8List imageData, double sigma) async {
  final startTime = DateTime.now();
  // decode image
  final (image, imgByteData) = await _decodeImage(imageData);
  final decodeTime = DateTime.now();
  final decodeMs = decodeTime.difference(startTime).inMilliseconds;

  // Create Gaussian kernel
  const int kernelSize = 5;
  const int kernelRadius = kernelSize ~/ 2;
  final List<List<double>> kernel = create2DGaussianKernel(kernelSize, sigma);

  // process image
  const int requiredWidth = 256;
  const int requiredHeight = 256;
  const int requiredSize = 4 * requiredWidth * requiredHeight;
  final scale = max(requiredWidth / image.width, requiredHeight / image.height);
  final scaledWidth = (image.width * scale).round();
  final scaledHeight = (image.height * scale).round();
  final widthOffset = max(0, scaledWidth - requiredWidth) / 2;
  final heightOffset = max(0, scaledHeight - requiredHeight) / 2;

  final processedBytes = Uint8List(requiredSize);
  int pixelIndex = 0;
  for (var h = 0 + heightOffset; h < scaledHeight - heightOffset; h++) {
    for (var w = 0 + widthOffset; w < scaledWidth - widthOffset; w++) {
      final Color pixel = _getPixelBilinearAntialias(
        w / scale,
        h / scale,
        image,
        imgByteData,
        kernel,
        kernelSize,
        kernelRadius,
      );
      processedBytes[pixelIndex] = pixel.red;
      processedBytes[pixelIndex + 1] = pixel.green;
      processedBytes[pixelIndex + 2] = pixel.blue;
      processedBytes[pixelIndex + 3] = 255;
      pixelIndex += 4;
    }
  }
  final processTime = DateTime.now();
  final processMs = processTime.difference(decodeTime).inMilliseconds;

  // encode image
  final encoded =
      await _encodeData(processedBytes, requiredWidth, requiredHeight);

  final encodeTime = DateTime.now();
  final encodeMs = encodeTime.difference(processTime).inMilliseconds;
  final totalMs = encodeTime.difference(startTime).inMilliseconds;
  log("Time for antialias downscale: total=$totalMs ms, process=$processMs ms, decode=$decodeMs ms, encode=$encodeMs ms");
  return encoded;
}

Future<Uint8List> processDownscaleImageWithAntialiasFaster(
    Uint8List imageData, double sigma) async {
  final startTime = DateTime.now();
  // decode image
  final (image, rgbaBytes) = await _decodeImageInt8Bytes(imageData);
  final decodeTime = DateTime.now();
  final decodeMs = decodeTime.difference(startTime).inMilliseconds;

  // Create Gaussian kernel
  const int kernelSize = 5;
  const int kernelRadius = kernelSize ~/ 2;
  final List<List<double>> kernel = create2DGaussianKernel(kernelSize, sigma);

  // process image
  const int requiredWidth = 256;
  const int requiredHeight = 256;
  const int requiredSize = 4 * requiredWidth * requiredHeight;
  final scale = max(requiredWidth / image.width, requiredHeight / image.height);
  final scaledWidth = (image.width * scale).round();
  final scaledHeight = (image.height * scale).round();
  final widthOffset = max(0, scaledWidth - requiredWidth) / 2;
  final heightOffset = max(0, scaledHeight - requiredHeight) / 2;

  final processedBytes = Uint8List(requiredSize);
  int pixelIndex = 0;
  for (var h = 0 + heightOffset; h < scaledHeight - heightOffset; h++) {
    for (var w = 0 + widthOffset; w < scaledWidth - widthOffset; w++) {
      final RGB pixel = _getPixelBilinearAntialiasFaster(
        w / scale,
        h / scale,
        image,
        rgbaBytes,
        kernel,
        kernelSize,
        kernelRadius,
      );
      processedBytes[pixelIndex] = pixel.$1;
      processedBytes[pixelIndex + 1] = pixel.$2;
      processedBytes[pixelIndex + 2] = pixel.$3;
      processedBytes[pixelIndex + 3] = 255;
      pixelIndex += 4;
    }
  }
  final processTime = DateTime.now();
  final processMs = processTime.difference(decodeTime).inMilliseconds;

  // encode image
  final encoded =
      await _encodeData(processedBytes, requiredWidth, requiredHeight);

  final encodeTime = DateTime.now();
  final encodeMs = encodeTime.difference(processTime).inMilliseconds;
  final totalMs = encodeTime.difference(startTime).inMilliseconds;
  log("Time for antialias FASTERale: total=$totalMs ms, process=$processMs ms, decode=$decodeMs ms, encode=$encodeMs ms");
  return encoded;
}

Future<Float32List> preprocessImageClip(
  Image image,
  ByteData imgByteData,
) async {
  const int requiredWidth = 256;
  const int requiredHeight = 256;
  const int requiredSize = 3 * requiredWidth * requiredHeight;
  final scale = max(requiredWidth / image.width, requiredHeight / image.height);
  final scaledWidth = (image.width * scale).round();
  final scaledHeight = (image.height * scale).round();
  final widthOffset = max(0, scaledWidth - requiredWidth) / 2;
  final heightOffset = max(0, scaledHeight - requiredHeight) / 2;

  final processedBytes = Float32List(requiredSize);
  final buffer = Float32List.view(processedBytes.buffer);
  int pixelIndex = 0;
  const int greenOff = requiredHeight * requiredWidth;
  const int blueOff = 2 * requiredHeight * requiredWidth;
  for (var h = 0 + heightOffset; h < scaledHeight - heightOffset; h++) {
    for (var w = 0 + widthOffset; w < scaledWidth - widthOffset; w++) {
      final Color pixel = _getPixelBilinear(
        w / scale,
        h / scale,
        image,
        imgByteData,
      );
      buffer[pixelIndex] = pixel.red / 255;
      buffer[pixelIndex + greenOff] = pixel.green / 255;
      buffer[pixelIndex + blueOff] = pixel.blue / 255;
      pixelIndex++;
    }
  }

  return processedBytes;
}

Color _getPixelBilinear(num fx, num fy, Image image, ByteData byteDataRgba) {
  // Clamp to image boundaries
  fx = fx.clamp(0, image.width - 1);
  fy = fy.clamp(0, image.height - 1);

  // Get the surrounding coordinates and their weights
  final int x0 = fx.floor();
  final int x1 = fx.ceil();
  final int y0 = fy.floor();
  final int y1 = fy.ceil();
  final dx = fx - x0;
  final dy = fy - y0;
  final dx1 = 1.0 - dx;
  final dy1 = 1.0 - dy;

  // Get the original pixels
  final Color pixel1 = _readPixelColor(image, byteDataRgba, x0, y0);
  final Color pixel2 = _readPixelColor(image, byteDataRgba, x1, y0);
  final Color pixel3 = _readPixelColor(image, byteDataRgba, x0, y1);
  final Color pixel4 = _readPixelColor(image, byteDataRgba, x1, y1);

  int bilinear(
    num val1,
    num val2,
    num val3,
    num val4,
  ) =>
      (val1 * dx1 * dy1 + val2 * dx * dy1 + val3 * dx1 * dy + val4 * dx * dy)
          .round();

  // Calculate the weighted sum of pixels
  final int r = bilinear(pixel1.red, pixel2.red, pixel3.red, pixel4.red);
  final int g =
      bilinear(pixel1.green, pixel2.green, pixel3.green, pixel4.green);
  final int b = bilinear(pixel1.blue, pixel2.blue, pixel3.blue, pixel4.blue);

  return Color.fromRGBO(r, g, b, 1.0);
}

Color _getPixelBilinearAntialias(
    num fx,
    num fy,
    Image image,
    ByteData byteDataRgba,
    List<List<double>> kernel,
    int kernelSize,
    int kernelRadius) {
  // Clamp to image boundaries
  fx = fx.clamp(0, image.width - 1);
  fy = fy.clamp(0, image.height - 1);

  // Get the surrounding coordinates and their weights
  final int x0 = fx.floor();
  final int x1 = fx.ceil();
  final int y0 = fy.floor();
  final int y1 = fy.ceil();
  final dx = fx - x0;
  final dy = fy - y0;
  final dx1 = 1.0 - dx;
  final dy1 = 1.0 - dy;

  // Get the original pixels
  final Color pixel1 = _getPixelGaussianBlur(
      image, byteDataRgba, x0, y0, kernel, kernelSize, kernelRadius);
  final Color pixel2 = _getPixelGaussianBlur(
      image, byteDataRgba, x1, y0, kernel, kernelSize, kernelRadius);
  final Color pixel3 = _getPixelGaussianBlur(
      image, byteDataRgba, x0, y1, kernel, kernelSize, kernelRadius);
  final Color pixel4 = _getPixelGaussianBlur(
      image, byteDataRgba, x1, y1, kernel, kernelSize, kernelRadius);

  int bilinear(
    num val1,
    num val2,
    num val3,
    num val4,
  ) =>
      (val1 * dx1 * dy1 + val2 * dx * dy1 + val3 * dx1 * dy + val4 * dx * dy)
          .round();

  // Calculate the weighted sum of pixels
  final int r = bilinear(pixel1.red, pixel2.red, pixel3.red, pixel4.red);
  final int g =
      bilinear(pixel1.green, pixel2.green, pixel3.green, pixel4.green);
  final int b = bilinear(pixel1.blue, pixel2.blue, pixel3.blue, pixel4.blue);

  return Color.fromRGBO(r, g, b, 1.0);
}

Color _getPixelGaussianBlur(
  Image image,
  ByteData byteDataRgba,
  int x,
  int y,
  List<List<double>> kernel,
  int kernelSize,
  int kernelRadius,
) {
  double r = 0, g = 0, b = 0;
  for (int ky = 0; ky < kernelSize; ky++) {
    for (int kx = 0; kx < kernelSize; kx++) {
      final int px = (x - kernelRadius + kx);
      final int py = (y - kernelRadius + ky);

      final Color pixelColor = _readPixelColor(image, byteDataRgba, px, py);
      final double weight = kernel[ky][kx];

      r += pixelColor.red * weight;
      g += pixelColor.green * weight;
      b += pixelColor.blue * weight;
    }
  }
  return Color.fromRGBO(r.round(), g.round(), b.round(), 1.0);
}

RGB _getPixelBilinearAntialiasFaster(
    num fx,
    num fy,
    Image image,
    Uint8List rgbaBytes,
    List<List<double>> kernel,
    int kernelSize,
    int kernelRadius) {
  // Clamp to image boundaries
  fx = fx.clamp(0, image.width - 1);
  fy = fy.clamp(0, image.height - 1);

  // Get the surrounding coordinates and their weights
  final int x0 = fx.floor();
  final int x1 = fx.ceil();
  final int y0 = fy.floor();
  final int y1 = fy.ceil();
  final dx = fx - x0;
  final dy = fy - y0;
  final dx1 = 1.0 - dx;
  final dy1 = 1.0 - dy;

  // Get the original pixels
  final RGB pixel1 = _getPixelGaussianBlurFaster(
      image, rgbaBytes, x0, y0, kernel, kernelSize, kernelRadius);
  final RGB pixel2 = _getPixelGaussianBlurFaster(
      image, rgbaBytes, x1, y0, kernel, kernelSize, kernelRadius);
  final RGB pixel3 = _getPixelGaussianBlurFaster(
      image, rgbaBytes, x0, y1, kernel, kernelSize, kernelRadius);
  final RGB pixel4 = _getPixelGaussianBlurFaster(
      image, rgbaBytes, x1, y1, kernel, kernelSize, kernelRadius);

  int bilinear(
    num val1,
    num val2,
    num val3,
    num val4,
  ) =>
      (val1 * dx1 * dy1 + val2 * dx * dy1 + val3 * dx1 * dy + val4 * dx * dy)
          .round();

  // Calculate the weighted sum of pixels
  final int r = bilinear(pixel1.$1, pixel2.$1, pixel3.$1, pixel4.$1);
  final int g = bilinear(pixel1.$2, pixel2.$2, pixel3.$2, pixel4.$2);
  final int b = bilinear(pixel1.$3, pixel2.$3, pixel3.$3, pixel4.$3);

  return (r, g, b);
}

RGB _getPixelGaussianBlurFaster(
  Image image,
  Uint8List rgbaBytes,
  int x,
  int y,
  List<List<double>> kernel,
  int kernelSize,
  int kernelRadius,
) {
  double r = 0, g = 0, b = 0;
  for (int ky = 0; ky < kernelSize; ky++) {
    for (int kx = 0; kx < kernelSize; kx++) {
      final int px = (x - kernelRadius + kx);
      final int py = (y - kernelRadius + ky);

      final RGB pixelRgbTuple = _readPixelRgb(image, rgbaBytes, px, py);
      final double weight = kernel[ky][kx];

      r += pixelRgbTuple.$1 * weight;
      g += pixelRgbTuple.$2 * weight;
      b += pixelRgbTuple.$3 * weight;
    }
  }
  return (r.round(), g.round(), b.round());
}

/// Reads the pixel color at the specified coordinates.
Color _readPixelColor(
  Image image,
  ByteData byteData,
  int x,
  int y,
) {
  if (x < 0 || x >= image.width || y < 0 || y >= image.height) {
    if (y < -2 || y >= image.height + 2 || x < -2 || x >= image.width + 2) {
      log('[WARNING] `readPixelColor`: Invalid pixel coordinates, out of bounds');
    }
    return const Color.fromARGB(0, 0, 0, 0);
  }
  assert(byteData.lengthInBytes == 4 * image.width * image.height);

  final int byteOffset = 4 * (image.width * y + x);
  return Color(_rgbaToArgb(byteData.getUint32(byteOffset)));
}

int _rgbaToArgb(int rgbaColor) {
  final int a = rgbaColor & 0xFF;
  final int rgb = rgbaColor >> 8;
  return rgb + (a << 24);
}

RGB _readPixelRgb(
  Image image,
  Uint8List rgbaBytes,
  int x,
  int y,
) {
  if (x < 0 || x >= image.width || y < 0 || y >= image.height) {
    if (y < -2 || y >= image.height + 2 || x < -2 || x >= image.width + 2) {
      log('[WARNING] `readPixelColor`: Invalid pixel coordinates, out of bounds');
    }
    return const (0, 0, 0);
  }
  assert(rgbaBytes.lengthInBytes == 4 * image.width * image.height);

  final int byteOffset = 4 * (image.width * y + x);
  return (
    rgbaBytes[byteOffset], // red
    rgbaBytes[byteOffset + 1], // green
    rgbaBytes[byteOffset + 2] // blue
  );
}
