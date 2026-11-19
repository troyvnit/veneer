import 'package:flutter/material.dart';
import 'package:veneer/veneer.dart';

import '../app_icons.dart';
import '../data/travel.dart';

/// Books a stay in a sheet: on iOS 26 a real UIKit sheet running the
/// `staySheet` entrypoint (see main.dart), which reads the place from the
/// payload; elsewhere the same page in a Flutter sheet. Returns a summary of
/// the booking, or null.
Future<String?> openStaySheet(BuildContext context, Place place) async {
  final result = await showNativeSheet<Object?>(
    context: context,
    entrypoint: 'staySheet',
    payload: place.id,
    detents: const [NativeSheetDetent.medium, NativeSheetDetent.large],
    builder: (context) => StaySheet(placeId: place.id),
  );
  return result as String?;
}

/// Native controls laid out by Flutter: a segmented control for the kind of
/// stay, a menu for the length, a slider for the budget, switches for
/// filters, and a native alert to confirm.
class StaySheet extends StatefulWidget {
  const StaySheet({super.key, this.placeId});

  /// The place, or null to read it from the native sheet's payload.
  final String? placeId;

  @override
  State<StaySheet> createState() => _StaySheetState();
}

class _StaySheetState extends State<StaySheet> {
  Place? _place;
  int _kind = 0;
  int _nights = 5;
  double _budget = 260;
  bool _freeCancellation = true;
  bool _breakfast = false;
  int _selected = 0;

  static const _kinds = ['Hotel', 'Apartment', 'Hostel'];

  @override
  void initState() {
    super.initState();
    if (widget.placeId case final id?) {
      _setPlace(placeById(id));
    } else {
      NativeSheet.payload().then((payload) {
        if (mounted) setState(() => _setPlace(placeById(payload as String? ?? '')));
      });
    }
  }

  /// Starts the budget where most of the place's stays fit.
  void _setPlace(Place place) {
    _place = place;
    _budget = (place.budget * 2.4).clamp(60, 1000).roundToDouble();
  }

  List<(String, int, double, String)> get _stays {
    final place = _place!;
    final base = switch (_kind) {
      0 => place.budget * 1.4,
      1 => place.budget * 1.1,
      _ => place.budget * 0.45,
    };
    final names = switch (_kind) {
      0 => ['The ${place.name} Grand', 'Hotel Belvedere', 'Harbour House'],
      1 => ['Loft with a view', 'Old town studio', 'Garden apartment'],
      _ => ['Backpackers Inn', 'The Bunkhouse', 'Nomad Hostel'],
    };
    final images = [place.image, ...place.gallery];
    return [
      for (var i = 0; i < 3; i++)
        (names[i], (base * (1 + i * 0.35) + (_breakfast ? 18 : 0)).round(), 4.9 - i * 0.15, images[i % images.length]),
    ].where((s) => s.$2 <= _budget).toList();
  }

  Future<void> _reserve((String, int, double, String) stay) async {
    final total = stay.$2 * _nights;
    final choice = await showNativeAlert(
      context: context,
      title: 'Reserve ${stay.$1}?',
      message:
          '$_nights nights · ${_money(total)} total'
          '${_freeCancellation ? '\nFree cancellation until 48 hours before.' : ''}',
      actions: const [
        NativeAlertAction(title: 'Cancel', style: NativeAlertActionStyle.cancel),
        NativeAlertAction(title: 'Reserve', preferred: true),
      ],
      tint: accent,
    );
    if (choice != 1 || !mounted) return;
    await NativeSheet.close(context, '${stay.$1}, $_nights nights · ${_money(total)}');
  }

  /// Dollars with thousands separators: $1,330.
  static String _money(int dollars) {
    final digits = '$dollars';
    final buffer = StringBuffer('\$');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final place = _place;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: NativeNavigationBar(
        leading: NativeBarButton(
          icon: const NativeIcon.icon(AppIcons.close),
          title: 'Close',
          onPressed: () => NativeSheet.close(context),
        ),
        title: NativeBarTitle(title: 'Book a stay', subtitle: place?.title),
        child: place == null ? const SizedBox.shrink() : Builder(builder: _body),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final scheme = Theme.of(context).colorScheme;
    final stays = _stays;
    final label = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant);
    return ListView(
      padding: EdgeInsets.fromLTRB(20, padding.top + 8, 20, padding.bottom + 24),
      children: [
        SizedBox(
          width: double.infinity,
          child: NativeSegmentedControl(
            labels: _kinds,
            selectedIndex: _kind,
            onValueChanged: (i) => setState(() {
              _kind = i;
              _selected = 0;
            }),
          ),
        ),
        const SizedBox(height: 18),
        _Row(
          icon: AppIcons.calendarBlank,
          title: 'Apr 4',
          trailing: NativeMenuAnchor(
            title: 'Length of stay',
            items: [
              for (final n in const [3, 5, 7, 10])
                NativeMenuItem(
                  title: '$n nights',
                  checked: n == _nights,
                  onSelected: () => setState(() => _nights = n),
                ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$_nights nights', style: const TextStyle(fontSize: 17, color: accent)),
                const SizedBox(width: 4),
                const Icon(AppIcons.arrowsDownUp, size: 15, color: accent),
              ],
            ),
          ),
        ),
        _Row(
          icon: AppIcons.wallet,
          title: 'Up to \$${_budget.round()} a night',
          below: SizedBox(
            height: 34,
            child: NativeSlider(
              value: _budget,
              min: 40,
              max: 1000,
              activeColor: accent,
              onChanged: (v) => setState(() => _budget = v),
            ),
          ),
        ),
        _Row(
          icon: AppIcons.check,
          title: 'Free cancellation',
          trailing: NativeSwitch(
            value: _freeCancellation,
            activeColor: accent,
            onChanged: (v) => setState(() => _freeCancellation = v),
          ),
        ),
        _Row(
          icon: AppIcons.coffee,
          title: 'Breakfast included',
          trailing: NativeSwitch(
            value: _breakfast,
            activeColor: accent,
            onChanged: (v) => setState(() => _breakfast = v),
          ),
        ),
        const SizedBox(height: 18),
        Text('${stays.length} ${stays.length == 1 ? 'STAY' : 'STAYS'} IN ${_place!.name.toUpperCase()}', style: label),
        const SizedBox(height: 10),
        if (stays.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Nothing under \$${_budget.round()} a night. Try a bigger budget.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16),
            ),
          ),
        for (final (i, stay) in stays.indexed)
          _StayCard(stay: stay, nights: _nights, selected: i == _selected, onTap: () => setState(() => _selected = i)),
        if (stays.isNotEmpty) ...[
          const SizedBox(height: 14),
          GlassShape(
            height: 54,
            icon: const NativeIcon.icon(AppIcons.check),
            label: 'Reserve · ${_money(stays[_selected.clamp(0, stays.length - 1)].$2 * _nights)}',
            tint: accent,
            foreground: Colors.white,
            onTap: () => _reserve(stays[_selected.clamp(0, stays.length - 1)]),
          ),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.trailing, this.below});

  final IconData icon;
  final String title;
  final Widget? trailing;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 17))),
              ?trailing,
            ],
          ),
          if (below != null) Padding(padding: const EdgeInsets.only(top: 8), child: below),
        ],
      ),
    );
  }
}

class _StayCard extends StatelessWidget {
  const _StayCard({required this.stay, required this.nights, required this.selected, required this.onTap});

  final (String, int, double, String) stay;
  final int nights;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (name, price, rating, image) = stay;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? accent : Colors.transparent, width: 2),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(image, width: 72, height: 72, fit: BoxFit.cover, cacheWidth: 216),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(AppIcons.starFill, size: 13, color: Color(0xFFFFB800)),
                      const SizedBox(width: 3),
                      Text(rating.toStringAsFixed(1), style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('\$$price', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                Text('a night', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}
