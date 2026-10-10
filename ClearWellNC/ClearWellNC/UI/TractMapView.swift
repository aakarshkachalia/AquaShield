//
//  TractMapView.swift
//  ClearWellNC
//
//  MKMapView wrapper. SwiftUI's Map is too slow with 2,000+ polygons, so tracts are grouped into
//  a handful of MKMultiPolygon overlays (one per risk level, split by tested/untested for opacity).
//

import MapKit
import SwiftUI

struct TractMapView: UIViewRepresentable {
    let database: TractDatabase
    let contaminant: Contaminant
    let selectedFIPS: String?
    let onTap: (CLLocationCoordinate2D) -> Void

    static let northCarolina = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.25, longitude: -79.85),
        span: MKCoordinateSpan(latitudeDelta: 3.6, longitudeDelta: 8.8))

    func makeCoordinator() -> Coordinator {
        Coordinator(database: database)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsUserLocation = false
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        map.setRegion(Self.northCarolina, animated: false)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTap = onTap
        coordinator.show(contaminant, on: map)
        coordinator.highlight(fips: selectedFIPS, on: map)
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        private struct Style {
            let level: RiskLevel
            let tested: Bool
        }

        let database: TractDatabase
        var onTap: (CLLocationCoordinate2D) -> Void = { _ in }

        /// MKPolygons for each tract, parallel to `database.tracts`. Built once, reused on every regroup.
        private lazy var tractPolygons: [[MKPolygon]] = database.tracts.map(Self.polygons(for:))

        private var shownContaminant: Contaminant?
        private var levelOverlays: [MKMultiPolygon] = []
        private var styles: [ObjectIdentifier: Style] = [:]
        private var highlightOverlay: MKMultiPolygon?
        private var highlightedFIPS: String?

        init(database: TractDatabase) {
            self.database = database
        }

        /// Regroups tracts into one overlay per (level, tested) for the chosen contaminant.
        func show(_ contaminant: Contaminant, on map: MKMapView) {
            guard contaminant != shownContaminant else { return }
            shownContaminant = contaminant

            map.removeOverlays(levelOverlays)
            levelOverlays.removeAll()
            styles.removeAll()

            let statewide = database.meta.statewideRate(for: contaminant)
            var buckets: [RiskLevel: (tested: [MKPolygon], untested: [MKPolygon])] = [:]
            for (index, tract) in database.tracts.enumerated() {
                guard let data = tract.data[contaminant] else { continue }
                let ratio = statewide > 0 ? data.estimate / statewide : 0
                let level = RiskLevel.level(forRatio: ratio)
                if data.tests > 0 {
                    buckets[level, default: ([], [])].tested += tractPolygons[index]
                } else {
                    buckets[level, default: ([], [])].untested += tractPolygons[index]
                }
            }

            // Light to dark, so darker (higher-risk) fills draw on top along shared borders.
            for level in [RiskLevel.lowerThanTypical, .typical, .elevated, .high] {
                guard let bucket = buckets[level] else { continue }
                for (polygons, tested) in [(bucket.untested, false), (bucket.tested, true)] where !polygons.isEmpty {
                    let overlay = MKMultiPolygon(polygons)
                    styles[ObjectIdentifier(overlay)] = Style(level: level, tested: tested)
                    levelOverlays.append(overlay)
                }
            }
            map.addOverlays(levelOverlays, level: .aboveRoads)

            // Keep the highlight above the new fills.
            if let highlightOverlay {
                map.removeOverlay(highlightOverlay)
                map.addOverlay(highlightOverlay, level: .aboveRoads)
            }
        }

        func highlight(fips: String?, on map: MKMapView) {
            guard fips != highlightedFIPS else { return }
            highlightedFIPS = fips
            if let highlightOverlay { map.removeOverlay(highlightOverlay) }
            highlightOverlay = nil
            guard let fips, let tract = database.tract(fips: fips) else { return }
            let overlay = MKMultiPolygon(Self.polygons(for: tract))
            highlightOverlay = overlay
            map.addOverlay(overlay, level: .aboveRoads)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let map = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: map)
            onTap(map.convert(point, toCoordinateFrom: map))
        }

        // Let the map's own pan/zoom gestures keep working alongside our tap.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let multi = overlay as? MKMultiPolygon else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKMultiPolygonRenderer(multiPolygon: multi)
            if multi === highlightOverlay {
                renderer.fillColor = .clear
                renderer.strokeColor = UIColor(white: 0.08, alpha: 1)
                renderer.lineWidth = 3
            } else if let style = styles[ObjectIdentifier(multi)] {
                renderer.fillColor = UIColor(style.level.color).withAlphaComponent(style.tested ? 0.75 : 0.35)
                renderer.strokeColor = UIColor.white.withAlphaComponent(0.8)
                renderer.lineWidth = 0.4
            }
            return renderer
        }

        private nonisolated static func polygons(for tract: Tract) -> [MKPolygon] {
            tract.polygons.map { polygon in
                let outer = polygon.outer.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                let holes = polygon.holes.map { ring in
                    let coords = ring.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                    return MKPolygon(coordinates: coords, count: coords.count)
                }
                return MKPolygon(coordinates: outer, count: outer.count, interiorPolygons: holes)
            }
        }
    }
}
