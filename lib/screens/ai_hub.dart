import 'package:flutter/material.dart';
import 'ocr_studio.dart';

const Color kNavyPrimary = Color(0xFF0F172A);
const Color kBlueAccent = Color(0xFF2563EB);
const Color kStudioLightBg = Color(0xFFF8FAFC);
const Color kWhitePure = Colors.white;
const Color kBorderSubtle = Color(0xFFE2E8F0);
const Color kSlateMuted = Color(0xFF64748B);

class AiStudioHubScreen extends StatelessWidget {
  const AiStudioHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kStudioLightBg,
      appBar: AppBar(
        backgroundColor: kWhitePure,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        shape: const Border(bottom: BorderSide(color: kBorderSubtle)),
        title: const Text('AI Studio Hub', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: kNavyPrimary)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('AI & OCR EXTRACTION TOOLS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: kSlateMuted, letterSpacing: 0.8)),
          const SizedBox(height: 12),
          _buildHubCard(
            context,
            icon: Icons.translate_rounded,
            title: 'Trilingual OCR Studio',
            subtitle: 'Extract text in English, Hindi, and Punjabi Gurmukhi',
            color: const Color(0xFF0D9488),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrilingualOcrStudioScreen())),
          ),
          const SizedBox(height: 12),
          _buildHubCard(
            context,
            icon: Icons.receipt_long_rounded,
            title: 'Smart Invoice Extractor',
            subtitle: 'Parse line items, totals, and GST amounts automatically',
            color: const Color(0xFFD97706),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Invoice extractor ready. Select an invoice via CamScanner.')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHubCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: kWhitePure,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kBorderSubtle),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5, color: kNavyPrimary)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: kSlateMuted)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16, color: kSlateMuted),
            ],
          ),
        ),
      ),
    );
  }
}
