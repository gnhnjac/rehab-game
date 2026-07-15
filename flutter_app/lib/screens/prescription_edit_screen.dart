// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../models/game_prescription.dart';
import '../state/app_state_scope.dart';
import '../widgets/prescription_summary_card.dart';

class PrescriptionEditScreen extends StatefulWidget {
  final String patientId;
  final GamePrescription prescription;

  const PrescriptionEditScreen({
    super.key,
    required this.patientId,
    required this.prescription,
  });

  @override
  State<PrescriptionEditScreen> createState() => _PrescriptionEditScreenState();
}

class _PrescriptionEditScreenState extends State<PrescriptionEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _cyclesController;
  late final TextEditingController _timerOrHoldController;
  late final TextEditingController _targetController;
  late int _selectedDifficulty;

  @override
  void initState() {
    super.initState();
    final p = widget.prescription;
    _cyclesController = TextEditingController(text: p.cycles.toString());
    if (p is CubesBoxesPrescription) {
      _selectedDifficulty = p.difficulty;
    } else {
      _selectedDifficulty = 2;
    }
    switch (p) {
      case CubesBoxesPrescription cb:
        _timerOrHoldController = TextEditingController(text: cb.timerSeconds.toString());
        _targetController = TextEditingController();
      case PinchPrescription pinch:
        _timerOrHoldController =
            TextEditingController(text: pinch.holdDurationSeconds.toString());
        _targetController = TextEditingController();
      case BendPrescription bend:
        _timerOrHoldController =
            TextEditingController(text: bend.holdDurationSeconds.toString());
        _targetController =
            TextEditingController(text: bend.targetRomPercent.toStringAsFixed(0));
    }
  }

  @override
  void dispose() {
    _cyclesController.dispose();
    _timerOrHoldController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  String? _validatePositiveInt(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed <= 0) return 'Enter a positive whole number';
    return null;
  }

  String? _validatePositiveDouble(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final parsed = double.tryParse(value.trim());
    if (parsed == null || parsed <= 0) return 'Enter a positive number';
    return null;
  }

  String? _validateRomPercent(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final parsed = double.tryParse(value.trim());
    if (parsed == null || parsed <= 0 || parsed > 100) {
      return 'Enter a value between 0 and 100';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final cycles = int.parse(_cyclesController.text.trim());
    final p = widget.prescription;
    final GamePrescription updated;
    switch (p) {
      case CubesBoxesPrescription cb:
        updated = cb.copyWith(
          cycles: cycles,
          timerSeconds: int.parse(_timerOrHoldController.text.trim()),
          difficulty: _selectedDifficulty,
        );
      case PinchPrescription pinch:
        updated = pinch.copyWith(
          cycles: cycles,
          holdDurationSeconds: int.parse(_timerOrHoldController.text.trim()),
        );
      case BendPrescription bend:
        updated = bend.copyWith(
          cycles: cycles,
          holdDurationSeconds: int.parse(_timerOrHoldController.text.trim()),
          targetRomPercent: double.parse(_targetController.text.trim()),
        );
    }

    await AppStateScope.of(context).updatePrescription(widget.patientId, updated);

    if (mounted) {
      Navigator.pop(context, updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.prescription;
    final String timerOrHoldLabel;
    final bool showTargetField = p is BendPrescription;
    switch (p) {
      case CubesBoxesPrescription _:
        timerOrHoldLabel = 'Timer (seconds)';
      case PinchPrescription _:
        timerOrHoldLabel = 'Hold duration (seconds)';
      case BendPrescription _:
        timerOrHoldLabel = 'Hold duration (seconds)';
    }

    final color = gameTypeColor(p.type);

    return Scaffold(
      appBar: AppBar(
        title: Text('Edit ${gameTypeLabel(p.type)} Prescription'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color, color.withOpacity(0.65)],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(gameTypeIcon(p.type), color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      gameTypeLabel(p.type),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            TextFormField(
              controller: _cyclesController,
              decoration: const InputDecoration(labelText: 'Cycles'),
              keyboardType: TextInputType.number,
              validator: _validatePositiveInt,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _timerOrHoldController,
              decoration: InputDecoration(labelText: timerOrHoldLabel),
              keyboardType: TextInputType.number,
              validator: _validatePositiveInt,
            ),
            if (showTargetField) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _targetController,
                decoration: const InputDecoration(labelText: 'Target ROM (%)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: _validateRomPercent,
              ),
            ],
            if (p is CubesBoxesPrescription) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: _selectedDifficulty,
                decoration: const InputDecoration(
                  labelText: 'Game Difficulty Level',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Level 1: Fixed Target Box Color')),
                  DropdownMenuItem(value: 2, child: Text('Level 2: Varying Color & Target Weight')),
                  DropdownMenuItem(value: 3, child: Text('Level 3: Shape & Color Match')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedDifficulty = val);
                  }
                },
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
