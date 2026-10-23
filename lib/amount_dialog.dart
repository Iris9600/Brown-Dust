import 'package:flutter/material.dart';
import 'mission_data.dart';

class AmountDialog extends StatefulWidget {
  const AmountDialog({super.key, required this.initial});
  final Map<String, int> initial;
  @override
  State<AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<AmountDialog> {
  late final Map<String, TextEditingController> _controllers = {
    for (final resource in resourceNames)
      resource: TextEditingController(text: '${widget.initial[resource] ?? 0}'),
  };
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('实际获得资源'),
    content: Form(
      key: _form,
      child: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final resource in resourceNames)
                TextFormField(
                  controller: _controllers[resource],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: resource,
                    prefixIcon: Icon(
                      resource == '钻石'
                          ? Icons.diamond_outlined
                          : Icons.inventory_2_outlined,
                      size: 20,
                    ),
                  ),
                  validator: (value) {
                    final number = int.tryParse(value ?? '');
                    return number == null || number < 0 || number > 100000000
                        ? '请输入 0 至 100000000 的整数'
                        : null;
                  },
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, {
              for (final entry in _controllers.entries)
                entry.key: int.parse(entry.value.text),
            });
          }
        },
        child: const Text('保存'),
      ),
    ],
  );
}
