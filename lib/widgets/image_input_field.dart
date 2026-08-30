import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ImageInputField extends StatefulWidget {
  final Function(File pickedImage) onImageSelected;
  final String labelText;

  const ImageInputField({
    super.key,
    required this.onImageSelected,
    this.labelText = 'ถ่ายรูปหน้าจอเครื่องวัดความดัน / ใบแล็บ',
  });

  @override
  State<ImageInputField> createState() => _ImageInputFieldState();
}

class _ImageInputFieldState extends State<ImageInputField> {
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1024, // 🚀 แก้จาก 1920 เป็น 1024 ตาม Spec เดิม เพื่อกันแอปเด้ง
        maxHeight: 1024, // 🚀
        imageQuality: 80, // 🚀 ลดจาก 85 เป็น 80 เพื่อให้ส่งเข้า Gemini ได้เร็วที่สุด
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
        });
        widget.onImageSelected(_selectedImage!);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาดในการเลือกรูปภาพ: $e')),
      );
    }
  }

  void _showPickerBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.labelText,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _pickImage(ImageSource.camera);
                    },
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('ถ่ายรูป'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _pickImage(ImageSource.gallery);
                    },
                    icon: const Icon(Icons.photo_library),
                    label: const Text('เลือกจากคลัง'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _showPickerBottomSheet,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.green.shade300,
                style: BorderStyle.solid,
                width: 1.5,
              ),
            ),
            child: _selectedImage != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      children: [
                        Image.file(
                          _selectedImage!,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.contain,
                        ),
                        Positioned(
                          right: 8,
                          top: 8,
                          child: CircleAvatar(
                            backgroundColor: Colors.black54,
                            child: IconButton(
                              icon: const Icon(Icons.edit, color: Colors.white),
                              onPressed: _showPickerBottomSheet,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_a_photo_rounded,
                        size: 48,
                        color: Colors.green.shade700,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.labelText,
                        style: TextStyle(
                          color: Colors.green.shade900,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'แตะเพื่อถ่ายภาพหรือแนบไฟล์',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
