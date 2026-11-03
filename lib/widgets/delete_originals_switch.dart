import 'package:flutter/material.dart';
import '../l10n.dart';

/// Opt-in checkbox offered on "pick file(s) -> convert" screens to delete
/// the picked source file(s) once the result has been saved. Off by
/// default - deleting is a one-way action.
class DeleteOriginalsSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? label;

  const DeleteOriginalsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label ?? tr('Originaldatei(en) danach löschen', 'Delete original file(s) afterwards')),
      subtitle: Text(tr('Kann nicht rückgängig gemacht werden', 'Cannot be undone')),
    );
  }
}
