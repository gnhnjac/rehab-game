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

  // Bend specific state
  late List<bool> _bendActiveFingers;
  late List<int> _bendFingerRomTargets;
  late List<int> _bendSequence;

  static const List<String> _fingerNames = ['Thumb', 'Index', 'Middle', 'Ring', 'Pinky'];

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

    if (p is BendPrescription) {
      _bendActiveFingers = List<bool>.from(p.activeFingers);
      _bendFingerRomTargets = List<int>.from(p.fingerRomTargets);
      _bendSequence = List<int>.from(p.sequence);
    } else {
      _bendActiveFingers = List.filled(5, true);
      _bendFingerRomTargets = List.filled(5, 70);
      _bendSequence = [1, 2, 3, 4, 5];
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

    final p = widget.prescription;
    if (p is BendPrescription) {
      if (_bendActiveFingers.every((f) => !f)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('At least one finger must be active.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
        return;
      }
      if (_bendSequence.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The exercise sequence cannot be empty.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
        return;
      }
    }

    final cycles = int.parse(_cyclesController.text.trim());
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
          activeFingers: _bendActiveFingers,
          sequence: _bendSequence,
          fingerRomTargets: _bendFingerRomTargets,
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
            if (p is BendPrescription) ...[
              const SizedBox(height: 20),
              const Text(
                'Configure Fingers',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              ...List.generate(5, (idx) {
                final isActive = _bendActiveFingers[idx];
                final currentTarget = _bendFingerRomTargets[idx];
                final color = gameTypeColor(GameType.bend);
                return Card(
                  color: const Color(0xFF1E293B),
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isActive ? color.withOpacity(0.3) : Colors.white.withOpacity(0.05),
                      width: 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _fingerNames[idx],
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: isActive ? Colors.white : Colors.grey,
                              ),
                            ),
                            Switch(
                              value: isActive,
                              activeColor: color,
                              onChanged: (val) {
                                setState(() {
                                  _bendActiveFingers[idx] = val;
                                  if (!val) {
                                    _bendSequence.removeWhere((item) => item == idx + 1);
                                  } else {
                                    if (!_bendSequence.contains(idx + 1)) {
                                      _bendSequence.add(idx + 1);
                                    }
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                        if (isActive) ...[
                          Row(
                            children: [
                              Expanded(
                                child: Slider(
                                  value: currentTarget.toDouble(),
                                  min: 10,
                                  max: 100,
                                  divisions: 18,
                                  activeColor: color,
                                  inactiveColor: const Color(0xFF0F111A),
                                  label: '$currentTarget%',
                                  onChanged: (val) {
                                    setState(() {
                                      _bendFingerRomTargets[idx] = val.round();
                                    });
                                  },
                                ),
                              ),
                              Container(
                                width: 45,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  '$currentTarget%',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 20),
              const Text(
                'Exercise Sequence',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                'Fingers will be exercised in this order. Tap a chip to remove it.',
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
              const SizedBox(height: 12),
              if (_bendSequence.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orangeAccent.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Empty sequence! Add fingers below.',
                        style: TextStyle(color: Colors.orangeAccent, fontSize: 13),
                      ),
                    ],
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(_bendSequence.length, (sIdx) {
                    final fIdx = _bendSequence[sIdx] - 1;
                    return InputChip(
                      label: Text('${sIdx + 1}. ${_fingerNames[fIdx]}'),
                      backgroundColor: const Color(0xFF1E293B),
                      labelStyle: const TextStyle(color: Colors.white, fontSize: 12.5),
                      onDeleted: () {
                        setState(() {
                          _bendSequence.removeAt(sIdx);
                        });
                      },
                      deleteIconColor: Colors.redAccent,
                    );
                  }),
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  DropdownButton<int>(
                    hint: const Text('Add finger to sequence', style: TextStyle(fontSize: 13)),
                    dropdownColor: const Color(0xFF141722),
                    items: List.generate(5, (idx) {
                      if (!_bendActiveFingers[idx]) return null;
                      return DropdownMenuItem<int>(
                        value: idx + 1,
                        child: Text(_fingerNames[idx]),
                      );
                    }).whereType<DropdownMenuItem<int>>().toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _bendSequence.add(val);
                        });
                      }
                    },
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _bendSequence.clear();
                        for (int i = 0; i < 5; i++) {
                          if (_bendActiveFingers[i]) {
                            _bendSequence.add(i + 1);
                          }
                        }
                      });
                    },
                    style: TextButton.styleFrom(foregroundColor: gameTypeColor(GameType.bend)),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Reset Order', style: TextStyle(fontSize: 13)),
                  ),
                ],
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
                  DropdownMenuItem(value: 2, child: Text('Level 2: Varying Color')),
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
