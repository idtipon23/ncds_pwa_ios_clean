import 'package:flutter/material.dart';

class BmiBarChart extends StatelessWidget {
  final double bmi;
  final String? gender; // เผื่ออนาคตอยากทำ Logic แยกเพศเพิ่มเติม

  const BmiBarChart({super.key, required this.bmi, this.gender});

  // ฟังก์ชันคำนวณเกณฑ์และสีตามมาตรฐาน WHO สำหรับคนเอเชีย
  Map<String, dynamic> _getBmiStatus(double bmiValue) {
    if (bmiValue < 18.5) {
      return {'label': 'ผอม', 'color': Colors.blue};
    } else if (bmiValue >= 18.5 && bmiValue <= 22.9) {
      return {'label': 'ปกติ', 'color': Colors.green};
    } else if (bmiValue >= 23.0 && bmiValue <= 24.9) {
      return {'label': 'ท้วม', 'color': Colors.orangeAccent};
    } else if (bmiValue >= 25.0 && bmiValue <= 29.9) {
      return {'label': 'อ้วน', 'color': Colors.orange};
    } else {
      return {'label': 'อ้วนอันตราย', 'color': Colors.red};
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _getBmiStatus(bmi);
    final Color activeColor = status['color'];
    final String label = status['label'];

    // คำนวณตำแหน่งลูกศรชี้ (แบบง่ายๆ เทียบสัดส่วน)
    double alignment = -1.0;
    if (bmi < 15)
      alignment = -1.0;
    else if (bmi > 35)
      alignment = 1.0;
    else
      alignment = ((bmi - 15) / 20) * 2 - 1; // สเกลจาก 15 ถึง 35

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ดัชนีมวลกาย (BMI)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: activeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                      color: activeColor, fontWeight: FontWeight.bold),
                ),
              )
            ],
          ),
          const SizedBox(height: 8),
          Text(
            bmi.toStringAsFixed(1),
            style: TextStyle(
                fontSize: 28, fontWeight: FontWeight.bold, color: activeColor),
          ),
          const SizedBox(height: 16),
          // ลูกศรชี้ตำแหน่ง
          Align(
            alignment: Alignment(alignment, 0),
            child: Icon(Icons.arrow_drop_down, color: activeColor, size: 30),
          ),
          // แถบสี Barchart (Segmented)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Row(
              children: [
                Expanded(
                    flex: 2,
                    child: Container(height: 12, color: Colors.blue)), // < 18.5
                Expanded(
                    flex: 3,
                    child: Container(
                        height: 12, color: Colors.green)), // 18.5 - 22.9
                Expanded(
                    flex: 2,
                    child: Container(
                        height: 12, color: Colors.orangeAccent)), // 23.0 - 24.9
                Expanded(
                    flex: 3,
                    child: Container(
                        height: 12, color: Colors.orange)), // 25.0 - 29.9
                Expanded(
                    flex: 3,
                    child: Container(height: 12, color: Colors.red)), // >= 30.0
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ผอม', style: TextStyle(fontSize: 10, color: Colors.grey)),
              Text('อ้วนอันตราย',
                  style: TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          )
        ],
      ),
    );
  }
}
