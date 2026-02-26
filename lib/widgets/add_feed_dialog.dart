import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/feed_provider.dart';

class AddFeedDialog extends StatefulWidget {
  const AddFeedDialog({super.key});

  @override
  State<AddFeedDialog> createState() => _AddFeedDialogState();
}

class _AddFeedDialogState extends State<AddFeedDialog> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  TextEditingController? _autoCompleteCategoryController;
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add RSS Feed'),
      backgroundColor: Theme.of(context).colorScheme.surface,
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _urlController,
                decoration: InputDecoration(
                  labelText: 'Feed URL',
                  hintText:
                      'e.g. https://techcrunch.com/feed/', // Add clear hint here
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.1),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a URL';
                  }
                  final uri = Uri.tryParse(value.trim());
                  if (uri == null || !uri.isAbsolute) {
                    return 'Please enter a valid URL';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Site Name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.1),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Autocomplete<String>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  final provider = context.read<FeedProvider>();
                  final categories = provider.subscriptions
                      .map((s) => s.category)
                      .where((c) => c != 'Uncategorized' && c.isNotEmpty)
                      .toSet()
                      .toList();
                  if (textEditingValue.text.isEmpty) {
                    return categories;
                  }
                  return categories.where((String option) {
                    return option.toLowerCase().contains(
                      textEditingValue.text.toLowerCase(),
                    );
                  });
                },
                fieldViewBuilder:
                    (
                      context,
                      textEditingController,
                      focusNode,
                      onFieldSubmitted,
                    ) {
                      _autoCompleteCategoryController = textEditingController;
                      return TextFormField(
                        controller: textEditingController,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: 'Category (Optional)',
                          hintText: 'Technology, News, etc.',
                          suffixIcon: const Icon(Icons.arrow_drop_down),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.1),
                        ),
                        onFieldSubmitted: (String value) {
                          onFieldSubmitted();
                        },
                      );
                    },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final url = _urlController.text.trim();
              final name = _nameController.text.trim();
              String category =
                  _autoCompleteCategoryController?.text.trim() ?? '';
              if (category.isEmpty) {
                category = 'Uncategorized'; // Explicitly set if empty
              }

              // Explicitly wait or handle adding via provider
              final provider = context.read<FeedProvider>();
              provider
                  .addFeed(url, name, category)
                  .then((_) {
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  })
                  .catchError((error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error adding feed: $error')),
                      );
                    }
                  });
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Add'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();

    super.dispose();
  }
}
