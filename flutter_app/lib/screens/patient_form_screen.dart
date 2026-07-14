// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../models/patient.dart';
import '../state/app_state_scope.dart';

class PatientFormScreen extends StatefulWidget {
  final Patient? existingPatient;

  const PatientFormScreen({super.key, this.existingPatient});

  @override
  State<PatientFormScreen> createState() => _PatientFormScreenState();
}

class _PatientFormScreenState extends State<PatientFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _ageController;
  late final TextEditingController _notesController;

  bool get _isEditing => widget.existingPatient != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingPatient;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _ageController = TextEditingController(text: existing?.age?.toString() ?? '');
    _notesController = TextEditingController(text: existing?.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final ageText = _ageController.text.trim();
    final age = ageText.isEmpty ? null : int.parse(ageText);
    final notesText = _notesController.text.trim();
    final notes = notesText.isEmpty ? null : notesText;

    final appState = AppStateScope.of(context);
    try {
      if (_isEditing) {
        await appState.updatePatient(
          widget.existingPatient!.copyWith(name: name, age: age, notes: notes),
        );
      } else {
        await appState.addPatient(name: name, age: age, notes: notes);
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save patient: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Patient' : 'Add Patient'),
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
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
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
                    child: Icon(
                      _isEditing ? Icons.edit_rounded : Icons.person_add_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _isEditing ? 'Update patient details' : 'Enroll a new patient',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _ageController,
              decoration: const InputDecoration(labelText: 'Age (optional)'),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.trim().isEmpty) return null;
                final parsed = int.tryParse(value.trim());
                if (parsed == null || parsed <= 0) {
                  return 'Enter a valid positive age';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                foregroundColor: Colors.white,
              ),
              child: Text(_isEditing ? 'Save Changes' : 'Add Patient'),
            ),
          ],
        ),
      ),
    );
  }
}
