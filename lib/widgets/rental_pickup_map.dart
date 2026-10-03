import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/app_constants.dart';

// Uses the existing cross-platform map dependency, including on Flutter Web.
class RentalPickupMap extends StatefulWidget {
  const RentalPickupMap(
      {super.key,
      required this.latitude,
      required this.longitude,
      this.selected = true,
      this.onSelect});
  final double latitude, longitude;
  final bool selected;
  final void Function(double, double)? onSelect;
  @override
  State<RentalPickupMap> createState() => _RentalPickupMapState();
}

class _RentalPickupMapState extends State<RentalPickupMap> {
  final _controller = MapController();
  @override
  void didUpdateWidget(RentalPickupMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.latitude != oldWidget.latitude ||
        widget.longitude != oldWidget.longitude) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted)
          _controller.move(LatLng(widget.latitude, widget.longitude),
              _controller.camera.zoom < 10 ? 15 : _controller.camera.zoom);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FlutterMap(
          mapController: _controller,
          options: MapOptions(
              initialCenter: LatLng(widget.latitude, widget.longitude),
              initialZoom: widget.selected ? 15 : 5,
              onTap: widget.onSelect == null
                  ? null
                  : (_, point) =>
                      widget.onSelect!(point.latitude, point.longitude)),
          children: [
            TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.oto.tag'),
            if (widget.selected)
              MarkerLayer(markers: [
                Marker(
                    point: LatLng(widget.latitude, widget.longitude),
                    width: 44,
                    height: 44,
                    child: const Icon(Icons.location_on_rounded,
                        color: AppConstants.primaryColor,
                        size: 42,
                        shadows: [
                          Shadow(color: Colors.black54, blurRadius: 4)
                        ]))
              ]),
            RichAttributionWidget(attributions: [
              TextSourceAttribution('OpenStreetMap contributors',
                  onTap: () => launchUrl(
                      Uri.https('www.openstreetmap.org', '/copyright')))
            ]),
          ]);
}
