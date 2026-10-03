//
//  RouteOverview.swift
//  TransitDresden
//

import SwiftUI

/// Kopf der gewählten Verbindung im Stil von Apple Karten:
/// Dauer, Abfahrt und Ankunft, darunter der Ablauf als Symbolzeile
struct RouteOverview: View {
    let route: Route
    /// Feste Höhe jeder Zeile der Symbolzeile. Symbole und Badges sind unterschiedlich hoch, der Fußweg mit
    /// tiefgestellter Zahl am höchsten; so ergeben gleich viele Zeilen immer dieselbe Kartenhöhe.
    @ScaledMetric(relativeTo: .title2) private var stepRowHeight: CGFloat = 32

    var body: some View {
        summary
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(travelTimeText)
                    .font(.title2.bold())
                    .monospacedDigit()
                // jede Minute neu, weil die Ankunft bei reinem Fußweg von der aktuellen Uhrzeit abhängt
                TimelineView(.everyMinute) { context in
                    let lines = detailLines(at: context.date)
                    // Abfahrt und Ankunft je eine eigene Zeile, damit kein Teil getrennt wird
                    // passt alles in eine Zeile: mit Trennpunkt; sonst Umbruch zwischen Abfahrt und Ankunft
                    ViewThatFits(in: .horizontal) {
                        Text(lines.joined(separator: " · "))
                            .lineLimit(1)
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(lines, id: \.self) { line in
                                Text(line)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .font(.body)
                .foregroundStyle(.secondary)
            }

            FlowLayout(spacing: 6, lineSpacing: 10, rowHeight: stepRowHeight) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    switch step {
                    case .walk(let minutes):
                        WalkStep(minutes: minutes)
                    case .ride(let line, let mode):
                        LineBadge(line: line, color: mode.color)
                        Image(systemName: mode.systemImage)
                            .font(.title2)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(stepsAccessibilityLabel)
        }
    }

    // MARK: - Texte

    /// Gesamtdauer vom Losgehen bis zur Ankunft
    private var travelTimeText: String {
        guard let leaveTime = route.leaveTime, let arrival = route.arrivalTime else { return "–" }
        return "Dauer: \(Self.durationText(minutes: Int(arrival.timeIntervalSince(leaveTime) / 60)))"
    }

    private func detailLines(at date: Date) -> [String] {
        guard let arrival = arrival(at: date) else { return [] }
        var lines: [String] = []
        // Abfahrt des ersten Verkehrsmittels (nicht der Beginn des Fußwegs)
        if let ride = route.firstRide, let departure = ride.getStartTime() {
            // Wie Apple Karten: "planmäßig", wenn keine Echtzeit vorliegt
            let isRealtime = ride.RegularStops?.first?.DepartureRealTime != nil
            let label = isRealtime ? "Abfahrt" : "Planmäßige Abfahrt"
            lines.append("\(label): \(departure.formatted(date: .omitted, time: .shortened))")
        }
        lines.append("Ankunftszeit: \(arrival.formatted(date: .omitted, time: .shortened))")
        return lines
    }

    /// Geplante Ankunft; ein reiner Fußweg kann jederzeit beginnen, dann gilt: jetzt losgehen plus Dauer
    private func arrival(at date: Date) -> Date? {
        guard let arrival = route.arrivalTime else { return nil }
        guard route.isWalkOnly, let leaveTime = route.leaveTime else { return arrival }
        return date.addingTimeInterval(arrival.timeIntervalSince(leaveTime))
    }

    /// "9 Min." oder "4 Std. 9 Min."
    static func durationText(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 {
            return "\(rest) Min."
        }
        return rest == 0 ? "\(hours) Std." : "\(hours) Std. \(rest) Min."
    }

    // MARK: - Ablauf

    private enum Step {
        case walk(minutes: Int)
        case ride(line: String, mode: TransitMode)
    }

    /// Fußwege (aufeinanderfolgende zusammengefasst) und Fahrten; Treppen und Wartezeiten entfallen
    private var steps: [Step] {
        var result: [Step] = []
        for partialRoute in route.PartialRoutes {
            let mode = TransitMode(motType: partialRoute.Mot.type)
            if mode == .walk {
                let minutes = partialRoute.getDuration()
                guard minutes > 0 else { continue }
                if case .walk(let previous) = result.last {
                    result[result.count - 1] = .walk(minutes: previous + minutes)
                } else {
                    result.append(.walk(minutes: minutes))
                }
            } else if mode.isRide {
                result.append(.ride(line: partialRoute.Mot.Name ?? "", mode: mode))
            }
        }
        return result
    }

    private var stepsAccessibilityLabel: String {
        steps.map { step in
            switch step {
            case .walk(let minutes):
                "\(minutes) Minuten Fußweg"
            case .ride(let line, let mode):
                "\(mode.accessibilityName) \(line)"
            }
        }
        .joined(separator: ", dann ")
    }
}

/// Fußweg-Symbol mit tiefgestellter Minutenzahl
private struct WalkStep: View {
    let minutes: Int

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Image(systemName: "figure.walk")
                .font(.title2)
            Text("\(minutes)")
                .font(.system(.footnote, design: .rounded, weight: .bold))
                .baselineOffset(-6)
        }
    }
}

/// Farbiges Linien-Badge wie "66" oder "RB 21"
private struct LineBadge: View {
    let line: String
    let color: Color

    var body: some View {
        Text(line)
            .font(.title3.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color, in: RoundedRectangle(cornerRadius: 5))
    }
}

/// Verkehrsmittel eines Abschnitts, abgeleitet aus dem Typ der VVO-Schnittstelle
enum TransitMode {
    case walk
    case bus
    case tram
    case suburbanRailway
    case train
    case ferry
    case cableway
    case other

    init(motType: String) {
        switch motType {
        case "Footpath": self = .walk
        case "CityBus", "IntercityBus", "PlusBus", "Bus": self = .bus
        case "Tram": self = .tram
        case "SuburbanRailway", "RapidTransit": self = .suburbanRailway
        case "Train": self = .train
        case "Ferry": self = .ferry
        case "Cableway": self = .cableway
        default: self = .other // Treppen, eingefügte Wartezeiten, Unbekanntes
        }
    }

    /// Abschnitt mit einem Fahrzeug (kein Fußweg, keine Treppe, keine Wartezeit)
    var isRide: Bool {
        self != .walk && self != .other
    }

    var systemImage: String {
        switch self {
        case .walk: "figure.walk"
        case .bus: "bus.fill"
        case .tram: "lightrail.fill"
        case .suburbanRailway, .train: "tram.fill"
        case .ferry: "ferry.fill"
        case .cableway: "cablecar.fill"
        case .other: "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .bus: .blue
        case .tram: .orange
        case .suburbanRailway: .green
        case .train: .red
        case .ferry: .teal
        case .cableway: .brown
        case .walk, .other: .gray
        }
    }

    /// Bezeichnung einer Linie im Satz, z. B. "Die Buslinie 68".
    /// Zusammengeschrieben; nur "S-Bahn-Linie" wird durchgekoppelt, weil "S-Bahn" schon einen Bindestrich hat.
    var lineTitle: String {
        switch self {
        case .bus: "Buslinie"
        case .tram: "Straßenbahnlinie"
        case .suburbanRailway: "S-Bahn-Linie"
        case .train: "Zuglinie"
        case .ferry: "Fährlinie"
        case .cableway: "Seilbahnlinie"
        case .walk, .other: "Linie"
        }
    }

    var accessibilityName: String {
        switch self {
        case .walk: "Fußweg"
        case .bus: "Bus"
        case .tram: "Straßenbahn"
        case .suburbanRailway: "S-Bahn"
        case .train: "Zug"
        case .ferry: "Fähre"
        case .cableway: "Seilbahn"
        case .other: "Abschnitt"
        }
    }
}

/// Ordnet Elemente nebeneinander an und bricht in die nächste Zeile um, wenn der Platz nicht reicht
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    /// Feste Zeilenhöhe; ohne sie ist jede Zeile so hoch wie ihr höchstes Element
    var rowHeight: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, maxWidth: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                // Elemente einer Zeile vertikal zentrieren
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let neededWidth = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if neededWidth > maxWidth && !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = rowHeight ?? max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

#Preview {
    List {
        Section {
            RouteOverview(route: tripTmp.Routes[1])
        }
    }
}
