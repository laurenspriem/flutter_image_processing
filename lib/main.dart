import 'dart:async';
import 'dart:developer' show log;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_processing/image_ml_util.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: HomePage(title: 'Image Processing'),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});

  final String title;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ImagePicker picker = ImagePicker();
  Image? imageOriginal;
  Image? imageProcessed;
  Uint8List? imageOriginalData;
  Uint8List? imageProcessedData;
  late Size imageDisplaySize;
  int stockImageCounter = 0;
  final List<String> _stockImagePaths = [
    'assets/images/stock_images/singapore.jpg',
    'assets/images/stock_images/one_person.jpeg',
    'assets/images/stock_images/one_person2.jpeg',
    'assets/images/stock_images/one_person3.jpeg',
    'assets/images/stock_images/one_person4.jpeg',
    'assets/images/stock_images/group_of_people.jpeg',
    'assets/images/stock_images/sample_640x640.jpg',
  ];

  @override
  void initState() {
    super.initState();
  }

  void _pickImage() async {
    _cleanResult();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      imageOriginalData = await image.readAsBytes();
      setState(() {
        imageOriginal = Image.file(File(image.path));
      });
    } else {
      log('No image selected');
    }
  }

  void _stockImage() async {
    _cleanResult();
    final byteData = await rootBundle.load(_stockImagePaths[stockImageCounter]);
    imageOriginalData = byteData.buffer.asUint8List();
    setState(() {
      imageOriginal = Image.asset(_stockImagePaths[stockImageCounter]);
      stockImageCounter = (stockImageCounter + 1) % _stockImagePaths.length;
    });
  }

  Future<void> _downscaleImage() async {
    if (imageOriginalData == null) return;

    imageProcessedData = await processDownscaleImage(imageOriginalData!);
    setState(() {
      imageProcessed = Image.memory(imageProcessedData!);
    });
  }

  Future<void> _blurImage() async {
    if (imageOriginalData == null) return;

    imageProcessedData = await processBlurImage(imageOriginalData!, 200.0);
    setState(() {
      imageProcessed = Image.memory(imageProcessedData!);
    });
  }

  Future<void> _downscaleWithBlurImage() async {
    if (imageOriginalData == null) return;

    imageProcessedData =
        await processDownscaleImageWithAntialias(imageOriginalData!, 200);
    setState(() {
      imageProcessed = Image.memory(imageProcessedData!);
    });
  }

  Future<void> _downscaleWithBlurImageFaster() async {
    if (imageOriginalData == null) return;

    imageProcessedData =
        await processDownscaleImageWithAntialiasFaster(imageOriginalData!, 200);
    setState(() {
      imageProcessed = Image.memory(imageProcessedData!);
    });
  }

  void _cleanResult() {
    setState(() {
      imageProcessed = null;
      imageProcessedData = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    imageDisplaySize = Size(
      MediaQuery.of(context).size.width * 0.8,
      MediaQuery.of(context).size.width * 0.8 * 1.5,
    );
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(
          widget.title,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            Container(
              height: imageDisplaySize.height,
              width: imageDisplaySize.width,
              color: Colors.black,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  // Image container
                  Center(
                    child: imageOriginal != null
                        ? imageProcessed ?? imageOriginal!
                        : const Text(
                            'No image selected',
                            style: TextStyle(color: Colors.white),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(
                            Icons.image,
                            color: Colors.black,
                            size: 16,
                          ),
                          label: const Text(
                            'Gallery',
                            style: TextStyle(color: Colors.black, fontSize: 10),
                          ),
                          onPressed: _pickImage,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(50, 30),
                            backgroundColor: Colors.grey[200], // Button color
                            foregroundColor: Colors.black,
                            elevation: 1,
                          ),
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(
                            Icons.collections,
                            color: Colors.black,
                            size: 16,
                          ),
                          label: const Text(
                            'Stock',
                            style: TextStyle(color: Colors.black, fontSize: 10),
                          ),
                          onPressed: _stockImage,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(50, 30),
                            backgroundColor: Colors.grey[200], // Button color
                            foregroundColor: Colors.black,
                            elevation: 1, // Elevation (shadow)
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton.icon(
              icon: imageProcessed != null
                  ? const Icon(Icons.undo_outlined)
                  : const Icon(Icons.broken_image_outlined),
              label: imageProcessed != null
                  ? const Text('Back to original')
                  : const Text('Downscale image'),
              onPressed:
                  imageProcessed != null ? _cleanResult : _downscaleImage,
            ),
            imageProcessed == null
                ? ElevatedButton.icon(
                    icon: const Icon(Icons.image_sharp),
                    label: const Text('Blur image'),
                    onPressed: _blurImage,
                  )
                : const SizedBox.shrink(),
            imageProcessed == null
                ? ElevatedButton.icon(
                    icon: const Icon(Icons.image_sharp),
                    label: const Text('Downscale antialias'),
                    onPressed: _downscaleWithBlurImage,
                  )
                : const SizedBox.shrink(),
            imageProcessed == null
                ? ElevatedButton.icon(
                    icon: const Icon(Icons.image_sharp),
                    label: const Text('Antialias faster'),
                    onPressed: _downscaleWithBlurImageFaster,
                  )
                : const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}
