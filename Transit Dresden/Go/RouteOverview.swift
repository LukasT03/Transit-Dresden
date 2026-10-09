//
//  RouteOverview.swift
//  Transit Dresden
//

import SwiftUI

/// Kopf der gewählten Verbindung im Stil von Apple Karten:
/// Abfahrt, Dauer und Ankunft, darunter der Ablauf als Symbolzeile
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
                Text(titleText)
                    .font(.title2.bold())
                    .monospacedDigit()
                // jede Minute neu, weil die Ankunft bei reinem Fußweg von der aktuellen Uhrzeit abhängt
                TimelineView(.everyMinute) { context in
                    let lines = detailLines(at: context.date)
                    // Dauer und Ankunft je eine eigene Zeile, damit kein Teil getrennt wird
                    // passt alles in eine Zeile: mit Trennpunkt; sonst Umbruch zwischen Dauer und Ankunft
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
                ForEach(Array(route.legs.enumerated()), id: \.offset) { index, leg in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    switch leg {
                    case .walk(let minutes):
                        WalkStep(minutes: minutes)
                    case .ride(let ride):
                        let mode = TransitMode(motType: ride.Mot.type)
                        // ein Element, damit Linie und Symbol nur gemeinsam umbrechen
                        HStack(spacing: 6) {
                            LineBadge(line: ride.Mot.Name ?? "", color: mode.color)
                            Image(systemName: mode.systemImage)
                                .font(.title2)
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(stepsAccessibilityLabel)
        }
    }

    // MARK: - Texte

    /// Abfahrt; bei reinem Fußweg gibt es keine, dann steht oben die Dauer
    private var titleText: String {
        departureText ?? travelTimeText ?? "–"
    }

    /// Abfahrt des ersten Verkehrsmittels (nicht der Beginn des Fußwegs)
    private var departureText: String? {
        guard let ride = route.firstRide, let departure = ride.getStartTime() else { return nil }
        // Wie Apple Karten: "planmäßig", wenn keine Echtzeit vorliegt
        let isRealtime = ride.RegularStops?.first?.DepartureRealTime != nil
        let label = isRealtime ? "Abfahrt" : "Planmäßige Abfahrt"
        return "\(label): \(departure.formatted(date: .omitted, time: .shortened))"
    }

    /// Gesamtdauer vom Losgehen bis zur Ankunft
    private var travelTimeText: String? {
        guard let leaveTime = route.leaveTime, let arrival = route.arrivalTime else { return nil }
        return "Dauer: \(Self.durationText(minutes: Int(arrival.timeIntervalSince(leaveTime) / 60)))"
    }

    private func detailLines(at date: Date) -> [String] {
        guard let arrival = arrival(at: date) else { return [] }
        var lines: [String] = []
        // Dauer nur hier, wenn sie nicht schon anstelle der Abfahrt oben steht
        if departureText != nil, let travelTimeText {
            lines.append(travelTimeText)
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

    private var stepsAccessibilityLabel: String {
        route.legs.map { leg in
            switch leg {
            case .walk(let minutes):
                "\(minutes) Minuten Fußweg"
            case .ride(let ride):
                "\(TransitMode(motType: ride.Mot.type).accessibilityName) \(ride.Mot.Name ?? "")"
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
struct LineBadge: View {
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
