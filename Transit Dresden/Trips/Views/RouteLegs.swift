//
//  RouteLegs.swift
//  Transit Dresden
//

import SwiftUI

/// Ablauf einer Verbindung im Stil von Apple Karten: je eine Zeile für den Start, jeden Fußweg,
/// jede Fahrt und die Ankunft. Eine Fahrt belegt mehrere Listenzeilen, eine je Haltestelle; die Liste braucht
/// dafür `.environment(\.defaultMinListRowHeight, 0)`, sonst wären diese Zeilen höher als ihr Inhalt.
struct RouteLegs: View {
    let route: Route
    /// Name des Ziels in der Ankunftszeile
    let destinationName: String
    /// Ein- und Ausstiege, an denen der Steig gezeigt wird, weil dort mehrere bedient werden. Steht schon vor dem
    /// Anzeigen fest, damit der Ablauf nicht nachträglich wächst.
    let platformStops: Set<RegularStop>
    /// IDs der Haltestellen, an denen man gerade steht
    let nearbyStops: Set<String>

    var body: some View {
        let legs = route.legs
        LegRow {
            LegCircle(systemImage: "mappin", color: .red)
        } content: {
            LegTitle("Start", subtitle: startSubtitle)
        }
        ForEach(legs.indices, id: \.self) { index in
            switch legs[index] {
            case .walk(let minutes):
                LegRow {
                    Image(systemName: "figure.walk")
                        .font(.title)
                } content: {
                    LegTitle(walkTitle(at: index, in: legs), subtitle: walkSubtitle(at: index, in: legs, minutes: minutes))
                }
            case .ride(let ride):
                // Umstieg ohne Fußweg dazwischen, etwa am selben Bahnhof: eigene Zeile mit der Zeit bis zur Abfahrt
                if index > 0, case .ride(let previous) = legs[index - 1] {
                    TransferRow(previous: previous, next: ride)
                }
                RideRow(ride: ride, platformStops: platformStops)
                    // eigener Zustand je Fahrt, damit aufgeklappte Zwischenhalte beim Wischen nicht auf eine andere
                    // Verbindung übergehen; über Linie und Plan-Abfahrt, damit er Echtzeit-Updates übersteht
                    .id("\(ride.Mot.Name ?? "")|\(ride.RegularStops?.first?.DepartureTime ?? "")")
            }
        }
        LegRow {
            LegCircle(systemImage: "flag.checkered", color: .blue)
        } content: {
            LegTitle("Ankunft", subtitle: destinationName)
        }
    }

    /// "Mein Standort"; steht man schon an der Haltestelle der ersten Fahrt, deren Name
    private var startSubtitle: String {
        guard route.startsAtStop || platformAtStartStop != nil, let stop = route.firstRide?.RegularStops?.first else {
            return "Mein Standort"
        }
        return "Haltestelle \(stop.Name)"
    }

    /// Steig der ersten Fahrt, wenn man schon an deren Haltestelle steht, nur an einem anderen Steig
    private var platformAtStartStop: String? {
        guard !route.startsAtStop, let stop = route.firstRide?.RegularStops?.first, nearbyStops.contains(stop.DataId) else {
            return nil
        }
        return stop.getPlatform()
    }

    /// "Zur Haltestelle „Klosterteichplatz“ gehen", an derselben Haltestelle "Zu Steig 3 gehen" (beim Umsteigen
    /// oder wenn man dort schon an einem anderen Steig steht), ohne folgende Fahrt "Zum Ziel gehen"
    private func walkTitle(at index: Int, in legs: [RouteLeg]) -> String {
        guard index + 1 < legs.count, case .ride(let next) = legs[index + 1], let stop = next.RegularStops?.first else {
            return "Zum Ziel gehen"
        }
        if index == 0, let platform = platformAtStartStop {
            return "Zu \(platform) gehen"
        }
        if index > 0, case .ride(let previous) = legs[index - 1],
           previous.RegularStops?.last?.Name == stop.Name, let platform = stop.getPlatform() {
            return "Zu \(platform) gehen"
        }
        return "Zur Haltestelle „\(stop.Name)“ gehen"
    }

    /// Beim Umsteigen die Zeit bis zur nächsten Abfahrt, sonst die Dauer des Fußwegs
    private func walkSubtitle(at index: Int, in legs: [RouteLeg], minutes: Int) -> String {
        if index > 0, index + 1 < legs.count,
           case .ride(let previous) = legs[index - 1], case .ride(let next) = legs[index + 1],
           let transfer = transferMinutes(from: previous, to: next) {
            return "Umstiegszeit: \(RouteOverview.durationText(minutes: transfer))"
        }
        return "Ungefähr \(RouteOverview.durationText(minutes: minutes))"
    }
}

/// Minuten von der Ankunft der einen Fahrt bis zur Abfahrt der nächsten, mit Echtzeit. Ist der Anschluss durch
/// Verspätung rechnerisch nicht mehr zu schaffen, 0 statt einer negativen Zeit.
private func transferMinutes(from previous: PartialRoute, to next: PartialRoute) -> Int? {
    guard let arrival = previous.getEndTime(), let departure = next.getStartTime() else { return nil }
    return max(Int(departure.timeIntervalSince(arrival) / 60), 0)
}

/// Umstieg zwischen zwei Fahrten ohne Fußweg dazwischen: zu einem anderen Gleis oder Steig gehen,
/// sonst bleiben und warten
private struct TransferRow: View {
    let previous: PartialRoute
    let next: PartialRoute

    var body: some View {
        let walkTitle = walkTitle
        LegRow {
            Image(systemName: walkTitle == nil ? "clock" : "figure.walk")
                .font(.title)
        } content: {
            if let walkTitle {
                LegTitle(walkTitle, subtitle: timeText("Umstiegszeit"))
            } else {
                LegTitle(stayTitle, subtitle: timeText("Wartezeit"))
            }
        }
    }

    private var arrival: RegularStop? {
        previous.RegularStops?.last
    }

    private var departure: RegularStop? {
        next.RegularStops?.first
    }

    /// "Zur Haltestelle „Postplatz“ gehen" oder "Zu Gleis 1 gehen"; nil, wenn man bleiben kann, wo man aussteigt
    private var walkTitle: String? {
        guard let arrival, let departure else { return nil }
        if arrival.Name != departure.Name {
            return "Zur Haltestelle „\(departure.Name)“ gehen"
        }
        if let platform = departure.getPlatform(), platform != arrival.getPlatform() {
            return "Zu \(platform) gehen"
        }
        return nil
    }

    /// Am Gleis "An Gleis 1 bleiben", bei Bus und Straßenbahn einfach "Umsteigen": Steige sind an den
    /// Haltestellen nur klein angeschrieben, dort ist der Umstieg meist selbsterklärend
    private var stayTitle: String {
        guard departure?.Platform?.type == "Railtrack", let platform = departure?.getPlatform() else {
            return "Umsteigen"
        }
        return "An \(platform) bleiben"
    }

    /// "Wartezeit: 6 Min."; ohne Zeiten nichts
    private func timeText(_ label: String) -> String? {
        transferMinutes(from: previous, to: next).map { "\(label): \(RouteOverview.durationText(minutes: $0))" }
    }
}

/// Zeile des Ablaufs: Symbol in fester Spalte links, daneben der Inhalt. Die Trennlinie beginnt beim Inhalt.
private struct LegRow<Icon: View, Content: View>: View {
    var alignment: VerticalAlignment = .center
    /// Kanten mit Innenabstand; die Zeilen einer Fahrt schließen ohne Abstand aneinander an
    var paddedEdges: Edge.Set = .vertical
    @ViewBuilder let icon: Icon
    @ViewBuilder let content: Content
    /// Feste Breite, damit alle Texte untereinander fluchten; reicht für dreistellige Liniennummern
    @ScaledMetric(relativeTo: .title3) private var iconWidth: CGFloat = 48

    var body: some View {
        HStack(alignment: alignment, spacing: 12) {
            icon
                .frame(width: iconWidth)
            VStack(alignment: .leading, spacing: 2) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
        .padding(paddedEdges, 6)
    }
}

private struct LegTitle: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String?) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Weißes Symbol auf farbigem Kreis für Start und Ankunft
private struct LegCircle: View {
    let systemImage: String
    let color: Color
    @ScaledMetric(relativeTo: .title3) private var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: Circle())
    }
}

// MARK: - Fahrt

/// Fahrt mit einem Verkehrsmittel: Linie und Richtung, darunter die Strecke in Linienfarbe mit Einstieg, der Zahl
/// der Haltestellen und Ausstieg, dort mit Steig, sofern die Haltestelle mehrere hat. Antippen der Zahl zeigt alle
/// Zwischenhalte.
/// Kopf und jeder Abschnitt der Strecke sind eigene Listenzeilen, lückenlos und ohne Trennlinie dazwischen. So fügt
/// die Liste aufgeklappte Zwischenhalte als Zeilen ein und schiebt nur den Ausstieg und alles darunter nach unten.
/// Wüchse stattdessen eine einzelne Zeile, bewegte die Liste während der Animation deren ganzen Inhalt.
private struct RideRow: View {
    let ride: PartialRoute
    /// Ein- und Ausstiege, an denen der Steig gezeigt wird
    let platformStops: Set<RegularStop>
    @State private var showsAllStops = false

    var body: some View {
        LegRow(alignment: .firstTextBaseline, paddedEdges: .top) {
            LineBadge(line: ride.Mot.Name ?? "", color: mode.color)
                // lange Liniennamen verkleinern, statt die Symbolspalte zu sprengen
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        } content: {
            Text([mode.accessibilityName, ride.Mot.Name].compactMap { $0 }.joined(separator: " "))
                .font(.title3.weight(.semibold))
            if let direction = ride.Mot.Direction {
                Text("Richtung „\(direction)“")
                    .foregroundStyle(.secondary)
            }
        }
        // Abstand zur Strecke, die ohne Innenabstand der Liste anschließt
        .padding(.bottom, 10)
        .listRowInsets(.bottom, 0)
        .listRowSeparator(.hidden, edges: .bottom)
        if let first = stops.first {
            stopRow(first, part: .boarding)
        }
        if let last = stops.last, stops.count > 1 {
            summaryRow
            if showsAllStops {
                ForEach(intermediateStops, id: \.self) { stop in
                    stopRow(stop, part: .intermediate)
                }
            }
            stopRow(last, part: .alighting)
        }
    }

    private var mode: TransitMode {
        TransitMode(motType: ride.Mot.type)
    }

    private var stops: [RegularStop] {
        ride.RegularStops ?? []
    }

    private var intermediateStops: [RegularStop] {
        Array(stops.dropFirst().dropLast())
    }

    /// Steig nur an Ein- und Ausstieg und nur, wo es mehrere gibt
    private func showsPlatform(of stop: RegularStop, at part: TrackPart) -> Bool {
        switch part {
        case .boarding, .alighting: platformStops.contains(stop)
        case .intermediate, .summary: false
        }
    }

    /// Zeile der Strecke, eingerückt bis zum Text des Kopfs. Erst nach dem Ausstieg folgen Abstand und Trennlinie.
    private func trackRow<Content: View>(_ part: TrackPart, @ViewBuilder content: () -> Content) -> some View {
        let closes = part == .alighting
        return LegRow(paddedEdges: closes ? .bottom : []) {
            // nur die Breite der Symbolspalte
            Color.clear
                .frame(height: 0)
        } content: {
            content()
        }
        .listRowInsets(closes ? .top : .vertical, 0)
        .listRowSeparator(.hidden, edges: closes ? .top : .all)
    }

    private func stopRow(_ stop: RegularStop, part: TrackPart) -> some View {
        trackRow(part) {
            TrackRow(part: part, color: mode.color) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(stop.Name)
                            .fontWeight(part == .intermediate ? .regular : .semibold)
                        if showsPlatform(of: stop, at: part), let platform = stop.getPlatform() {
                            Text(platform)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    StopTime(stop: stop, isDeparture: part == .boarding)
                }
            }
        }
    }

    private var summaryRow: some View {
        let part = TrackPart.summary(dotted: !showsAllStops)
        return trackRow(part) {
            TrackRow(part: part, color: mode.color) {
                if intermediateStops.isEmpty {
                    Text(summaryText)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        withAnimation {
                            showsAllStops.toggle()
                        }
                    } label: {
                        Text(summaryText)
                            .foregroundStyle(mode.color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(showsAllStops ? "Blendet die Zwischenhalte aus" : "Zeigt alle Zwischenhalte")
                }
            }
        }
    }

    /// "Fahrt: 9 Haltestellen, 12 Min."
    private var summaryText: String {
        let count = stops.count - 1
        return "Fahrt: \(count) \(count == 1 ? "Haltestelle" : "Haltestellen"), \(RouteOverview.durationText(minutes: ride.getDuration()))"
    }
}

private enum TrackPart: Equatable {
    /// Einstieg: Linie ab der Markierung nach unten
    case boarding
    case intermediate
    /// Ausstieg: Linie bis zur Markierung
    case alighting
    /// Zahl der Haltestellen; gepunktet, solange die Zwischenhalte zugeklappt sind
    case summary(dotted: Bool)
}

/// Zeile der Strecke: links ein Stück der Linie, die Markierung auf Höhe der ersten Textzeile.
/// Jede Zeile zeichnet ihr Stück über die volle Höhe, so geht die Linie lückenlos in die Nachbarzeilen über.
private struct TrackRow<Content: View>: View {
    let part: TrackPart
    let color: Color
    @ViewBuilder let content: Content
    /// Höhe einer Textzeile; die Markierung sitzt mittig darauf
    @ScaledMetric(relativeTo: .body) private var lineHeight: CGFloat = 22

    private let trackWidth: CGFloat = 16
    private let lineWidth: CGFloat = 4
    private let verticalPadding: CGFloat = 6

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, verticalPadding)
            .padding(.leading, trackWidth + 10)
            .background(alignment: .leading) {
                GeometryReader { proxy in
                    track(height: proxy.size.height)
                }
                .frame(width: trackWidth)
                .accessibilityHidden(true)
            }
    }

    @ViewBuilder
    private func track(height: CGFloat) -> some View {
        let markerY = verticalPadding + lineHeight / 2
        let center = CGPoint(x: trackWidth / 2, y: markerY)
        switch part {
        case .boarding:
            line(from: markerY, to: height)
                .stroke(color, lineWidth: lineWidth)
            Circle()
                .strokeBorder(color, lineWidth: 3.5)
                .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
                .frame(width: 15, height: 15)
                .position(center)
        case .intermediate:
            line(from: 0, to: height)
                .stroke(color, lineWidth: lineWidth)
            Circle()
                .strokeBorder(color, lineWidth: 2.5)
                .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
                .frame(width: 10, height: 10)
                .position(center)
        case .alighting:
            line(from: 0, to: markerY)
                .stroke(color, lineWidth: lineWidth)
            Circle()
                .fill(color)
                .frame(width: 15, height: 15)
                .position(center)
        case .summary(let dotted):
            if dotted {
                // runde Punkte im Abstand von 8, mit mindestens 8 Abstand zu den durchgezogenen Stücken darüber und
                // darunter; als Gruppe mittig, damit oben und unten gleich viel Luft bleibt
                let spacing: CGFloat = 8
                let count = max(Int((height - 2 * spacing) / spacing) + 1, 0)
                let top = (height - CGFloat(count - 1) * spacing) / 2
                ForEach(0..<count, id: \.self) { index in
                    Circle()
                        .fill(color)
                        .frame(width: lineWidth, height: lineWidth)
                        .position(x: trackWidth / 2, y: top + CGFloat(index) * spacing)
                }
            } else {
                line(from: 0, to: height)
                    .stroke(color, lineWidth: lineWidth)
            }
        }
    }

    private func line(from top: CGFloat, to bottom: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: trackWidth / 2, y: top))
            path.addLine(to: CGPoint(x: trackWidth / 2, y: max(top, bottom)))
        }
    }
}

/// Uhrzeit an einer Haltestelle, bei Echtzeit mit der Abweichung vom Fahrplan davor
private struct StopTime: View {
    let stop: RegularStop
    let isDeparture: Bool

    var body: some View {
        let time = isDeparture ? stop.getRealDepartureTime() : stop.getRealArrivalTime()
        let delay = isDeparture ? stop.getTimeDifferenceDeparture() : stop.getTimeDifference()
        HStack(spacing: 4) {
            if delay != 0 {
                Text(delay > 0 ? "+\(delay)" : "\(delay)")
                    .foregroundStyle(delay > 0 ? Color.red : Color.green)
            }
            Text(time)
                .foregroundStyle(.secondary)
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(time: time, delay: delay))
    }

    private func accessibilityText(time: String, delay: Int) -> String {
        var text = "\(isDeparture ? "Abfahrt" : "Ankunft") \(time) Uhr"
        let minutes = abs(delay)
        let unit = minutes == 1 ? "Minute" : "Minuten"
        if delay > 0 {
            text += ", \(minutes) \(unit) Verspätung"
        } else if delay < 0 {
            text += ", \(minutes) \(unit) früher"
        }
        return text
    }
}

#Preview {
    NavigationStack {
        List {
            Section {
                // Straßenbahn mit sechs Zwischenhalten zum Auf- und Zuklappen, Steige überall sichtbar
                RouteLegs(
                    route: tripTmp.Routes[0],
                    destinationName: "Nürnberger Platz",
                    platformStops: Set(tripTmp.Routes[0].boardingAndAlightingStops),
                    nearbyStops: []
                )
            }
        }
        .environment(\.defaultMinListRowHeight, 0)
    }
}
