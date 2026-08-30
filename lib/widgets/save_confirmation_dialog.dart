import 'dart:io';
import 'package:flutter/material.dart';

class SaveConfirmationDialog extends StatefulWidget {
  final Map<String, dynamic> healthData;
  final File? imageFile;
  final Function(Map<String, dynamic> updatedData) onConfirm;

  const SaveConfirmationDialog({
    super.key,
    required this.healthData,
    this.imageFile,
    required this.onConfirm,
  });

  @override
  State<SaveConfirmationDialog> createState() => _SaveConfirmationDialogState();
}

class _SaveConfirmationDialogState extends State<SaveConfirmationDialog> {
  late TextEditingController _sysController;
  late TextEditingController _diaController;
  late TextEditingController _pulseController;
  late TextEditingController _weightController; // 📍 เพิ่มช่องแก้ไขน้ำหนัก

  @override
  void initState() {
    super.initState();
    _sysController = TextEditingController(text: widget.healthData['systolic']?.toString() ?? '');
    _diaController = TextEditingController(text: widget.healthData['diastolic']?.toString() ?? '');
    _pulseController = TextEditingController(text: widget.healthData['pulse']?.toString() ?? '');
    _weightController = TextEditingController(text: widget.healthData['weight_kg']?.toString() ?? widget.healthData['weight']?.toString() ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('ตรวจสอบและยืนยันข้อมูล', style: TextStyle(fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('คุณสามารถแตะที่ตัวเลขเพื่อแก้ไขให้ถูกต้องได้', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildEditableField('ตัวบน (SYS)', _sysController)),
                const SizedBox(width: 8),
                Expanded(child: _buildEditableField('ตัวล่าง (DIA)', _diaController)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildEditableField('ชีพจร (Pulse)', _pulseController)),
                const SizedBox(width: 8),
                Expanded(child: _buildEditableField('น้ำหนัก (Kg)', _weightController)),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
              child: Text(
                'AI วิเคราะห์: ${widget.healthData['spoken_feedback'] ?? '-'}',
                style: TextStyle(fontSize: 13, color: Colors.blue.shade900),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          onPressed: () {
            // อัปเดตค่าใหม่กลับเข้าไป
            final updatedData = Map<String, dynamic>.from(widget.healthData);
            updatedData['systolic'] = int.tryParse(_sysController.text);
            updatedData['diastolic'] = int.tryParse(_diaController.text);
            updatedData['pulse'] = int.tryParse(_pulseController.text);
            updatedData['weight_kg'] = double.tryParse(_weightController.text);

            Navigator.pop(context);
            widget.onConfirm(updatedData); // ส่งข้อมูลที่แก้แล้วกลับไปให้ห้องตรวจบันทึก
          },
          child: const Text('บันทึกข้อมูล', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildEditableField(String label, TextEditingController controller) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}