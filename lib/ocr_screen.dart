import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'dart:math';
import 'ocr_utils.dart';

class RealTimeOCRScreen extends StatefulWidget {
  const RealTimeOCRScreen({super.key});

  @override
  _RealTimeOCRScreenState createState() => _RealTimeOCRScreenState();
}

class _RealTimeOCRScreenState extends State<RealTimeOCRScreen> {
  File? _nifImageFile;
  File? _activityCodeImageFile;
  late CameraController _cameraController;
  late TextRecognizer _textRecognizer;
  bool _isCameraInitialized = false;
  String _nifResult = "";
  String _activityCodeResult = "";
  int _frameCount = 0;
  bool _isProcessing = false;
  bool _nifDetected = false;
  bool _activityCodeDetected = false;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _textRecognizer = TextRecognizer();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final firstCamera = cameras.first;

      _cameraController = CameraController(
        firstCamera,
        ResolutionPreset.max,
        enableAudio: false,
      );

      await _cameraController.initialize();
      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
      });
    } catch (e) {
      print("Error initializing camera: $e");
    }
  }

  InputImageRotation _getInputImageRotation(CameraDescription camera) {
    final deviceOrientation =
        MediaQueryData.fromView(WidgetsBinding.instance.window).orientation;
    if (deviceOrientation == Orientation.landscape) {
      return camera.sensorOrientation == 90
          ? InputImageRotation.rotation90deg
          : InputImageRotation.rotation270deg;
    } else {
      return camera.sensorOrientation == 90
          ? InputImageRotation.rotation0deg
          : InputImageRotation.rotation180deg;
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isProcessing || (_nifDetected && _activityCodeDetected)) return;

    _frameCount++;
    if (_frameCount % 10 != 0) return;

    setState(() {
      _isProcessing = true;
    });

    final camera = _cameraController.description;
    final rotation = _getInputImageRotation(camera);

    final WriteBuffer allBytes = WriteBuffer();
    for (Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();
    final inputImageSize =
        Size(image.width.toDouble(), image.height.toDouble());
    final inputImageFormat =
        InputImageFormatValue.fromRawValue(image.format.raw) ??
            InputImageFormat.nv21;

    final inputImageData = InputImageMetadata(
      size: inputImageSize,
      rotation: rotation,
      format: inputImageFormat,
      bytesPerRow: image.planes[0].bytesPerRow,
    );

    final inputImage =
        InputImage.fromBytes(bytes: bytes, metadata: inputImageData);

    try {
      final recognizedText = await _textRecognizer.processImage(inputImage);
      final nif = _extractNIF(recognizedText.text);
      final activityCode = _extractActivityCode(recognizedText.text);

      // Detect NIF and capture image if not yet captured
      if (nif != null && !_nifDetected) {
        setState(() {
          _nifResult = nif;
          _nifDetected = true;
          _showMessage("NIF saved");
        });
        await _captureImage('NIF'); // Capture image for NIF
      }

      // Detect Activity Code and capture image if not yet captured
      if (activityCode != null && !_activityCodeDetected) {
        setState(() {
          _activityCodeResult = activityCode;
          _activityCodeDetected = true;
          _showMessage("Activity Code saved");
        });
        await _captureImage('Activity Code'); // Capture image for Activity Code
      }

      // Stop scanning when both NIF and Activity Code are detected
      if (_nifDetected && _activityCodeDetected) {
        _stopScanning();
      }
    } catch (e) {
      print("Error processing image: $e");
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _captureImage(String codeType) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final imageFile = await _cameraController.takePicture();

      // Save the image to the desired path
      final savedImageFile = File(
          '${directory.path}/${DateTime.now().millisecondsSinceEpoch}.jpg');
      await imageFile.saveTo(savedImageFile.path);

      print('Image captured and saved at: ${savedImageFile.path}');

      setState(() {
        if (codeType == 'NIF') {
          _nifImageFile = savedImageFile;
        } else if (codeType == 'Activity Code') {
          _activityCodeImageFile = savedImageFile;
        }
      });
    } catch (e) {
      print("Error capturing image: $e");
    }
  }

  void _openFile(File file) {
    OpenFile.open(file.path);
  }

  void _startScanning() {
    _cameraController.startImageStream(_processCameraImage);
    setState(() {
      _isScanning = true;
    });
  }

  void _stopScanning() {
    _cameraController.stopImageStream();
    setState(() {
      _isScanning = false;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String? _extractNIF(String text) {
    return OCRUtils.extractNIF(text);
  }

  String? _extractActivityCode(String text) {
    return OCRUtils.extractActivityCode(text);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: _isScanning
          ? LayoutBuilder(
              builder: (context, constraints) {
                double cameraHeight = constraints.maxHeight * 0.7;

                return Stack(
                  children: [
                    _buildCameraPreview(cameraHeight),
                    _buildResultSection(cameraHeight),
                  ],
                );
              },
            )
          : Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // NIF Display
                    TextField(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'NIF',
                      ),
                      controller: TextEditingController.fromValue(
                        TextEditingValue(
                          text: _nifResult,
                          selection: TextSelection.collapsed(
                            offset: _nifResult.length,
                          ),
                        ),
                      ),
                      readOnly: true,
                    ),
                    // Show "View NIF Image" button if NIF image is captured
                    if (_nifImageFile != null)
                      TextButton(
                        onPressed: () => _openFile(_nifImageFile!),
                        child: const Text('View NIF Image'),
                      ),

                    const SizedBox(height: 20),

                    // Activity Code Display
                    TextField(
                      decoration: InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Activity Code',
                        errorText: _activityCodeResult.startsWith('Invalid')
                            ? 'Invalid activity code'
                            : null,
                      ),
                      controller: TextEditingController.fromValue(
                        TextEditingValue(
                          text: _activityCodeResult,
                          selection: TextSelection.collapsed(
                            offset: _activityCodeResult.length,
                          ),
                        ),
                      ),
                      readOnly: true,
                      style: TextStyle(
                        color: _activityCodeResult.startsWith('Invalid')
                            ? Colors.red
                            : Colors.black,
                      ),
                    ),
                    // Show "View Activity Code Image" button if Activity Code image is captured
                    if (_activityCodeImageFile != null)
                      TextButton(
                        onPressed: () => _openFile(_activityCodeImageFile!),
                        child: const Text('View Activity Code Image'),
                      ),

                    const SizedBox(height: 20),

                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _nifResult = "";
                          _activityCodeResult = "";
                          _nifDetected = false;
                          _activityCodeDetected = false;
                        });
                        _startScanning();
                      },
                      child: const Text('Start Scanning'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildCameraPreview(double cameraHeight) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: cameraHeight,
      child: Transform.rotate(
        // angle: 0,
        angle: _cameraController.description.sensorOrientation * pi / 180,
        child: CameraPreview(_cameraController),
      ),
    );
  }

  Widget _buildResultSection(double cameraHeight) {
    return Positioned(
      top: cameraHeight,
      left: 0,
      right: 0,
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'NIF',
            ),
            controller: TextEditingController.fromValue(
              TextEditingValue(
                text: _nifResult,
                selection: TextSelection.collapsed(offset: _nifResult.length),
              ),
            ),
            readOnly: true,
          ),
          _nifImageFile != null
              ? TextButton(
                  onPressed: () => _openFile(_nifImageFile!),
                  child: const Text('View NIF Image'),
                )
              : const SizedBox.shrink(),
          const SizedBox(height: 20),
          TextField(
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Activity Code',
              errorText: _activityCodeResult.startsWith('Invalid')
                  ? 'Invalid activity code'
                  : null,
            ),
            controller: TextEditingController.fromValue(
              TextEditingValue(
                text: _activityCodeResult,
                selection:
                    TextSelection.collapsed(offset: _activityCodeResult.length),
              ),
            ),
            readOnly: true,
            style: TextStyle(
                color: _activityCodeResult.startsWith('Invalid')
                    ? Colors.red
                    : Colors.black),
          ),
          _activityCodeImageFile != null
              ? TextButton(
                  onPressed: () => _openFile(_activityCodeImageFile!),
                  child: const Text('View Activity Code Image'),
                )
              : const SizedBox.shrink(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _textRecognizer.close();
    super.dispose();
  }
}
