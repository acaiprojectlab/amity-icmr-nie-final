import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_provider.dart';
import '../../services/reference_data_service.dart';

class SymptomChipSelector extends StatefulWidget {
  const SymptomChipSelector({super.key});

  @override
  State<SymptomChipSelector> createState() => _SymptomChipSelectorState();
}

class _SymptomChipSelectorState extends State<SymptomChipSelector> {
  String _searchFilter = '';

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final sdn = ReferenceDataService.instance.symptomDisplayNames;
    final allSymptoms = ReferenceDataService.instance.allSymptoms;

    // Filter symptoms by search query
    final filteredSymptoms = allSymptoms.where((sym) {
      final displayName = sdn[sym] ?? sym;
      return displayName.toLowerCase().contains(_searchFilter.toLowerCase());
    }).toList();

    // Sort alphabetically by display name
    filteredSymptoms.sort((a, b) {
      final nameA = sdn[a] ?? a;
      final nameB = sdn[b] ?? b;
      return nameA.compareTo(nameB);
    });

    final activeCount =
        provider.symptoms.values.where((val) => val == 1).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search bar & Active Count
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search 35 clinical symptoms...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                        color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
                  ),
                  filled: true,
                  fillColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.3),
                ),
                onChanged: (val) {
                  setState(() {
                    _searchFilter = val.trim();
                  });
                },
              ),
            ),
            const SizedBox(width: 10),
            Chip(
              backgroundColor: activeCount > 0
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              label: Text(
                '$activeCount selected',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: activeCount > 0
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Symptom Chips
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: filteredSymptoms.map((symKey) {
            final displayName = sdn[symKey] ?? symKey;
            final isSelected = (provider.symptoms[symKey] ?? 0) == 1;

            return FilterChip(
              label: Text(displayName),
              selected: isSelected,
              onSelected: (_) {
                provider.toggleSymptom(symKey);
              },
              selectedColor: Theme.of(context).colorScheme.primary,
              checkmarkColor: Colors.white,
              labelStyle: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
                side: BorderSide(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).dividerColor.withValues(alpha: 0.4),
                  width: isSelected ? 1.5 : 0.8,
                ),
              ),
              backgroundColor: Theme.of(context).colorScheme.surface,
              showCheckmark: true,
            );
          }).toList(),
        ),
      ],
    );
  }
}
