//
//  GoView.swift
//  TransitDresden
//

import SwiftUI
import MapKit

/// Einfacher Weg zum Ziel: Ziel wählen, die App plant ab dem aktuellen Standort
struct GoView: View {
    @EnvironmentObject var favoriteStops: FavoriteStop
    @State private var model = GoViewModel()
    @State private var addressSearch = AddressSearch()
    @State private var searchText = ""
    @State private var recents: [ConnectionStop] = []

    var body: some View {
        NavigationStack {
            destinationPicker
        }
        .sheet(isPresented: isShowingResult) {
            NavigationStack {
                GoResultView(model: model)
                    .navigationDestination(for: Stop.self) { stop in
                        DepartureView(stop: stop)
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
    }

    /// Das Sheet ist offen, solange ein Ziel gewählt ist; Schließen setzt die Auswahl zurück
    private var isShowingResult: Binding<Bool> {
        Binding {
            model.destination != nil
        } set: { isPresented in
            if !isPresented {
                model.reset()
            }
        }
    }

    // MARK: - Ziel wählen

    private var destinationPicker: some View {
        List {
            if searchText.isEmpty {
                Section("Favoriten") {
                    if favoriteStopList.isEmpty {
                        Text("Noch keine favorisierten Haltestellen.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(favoriteStopList) { stop in
                        destinationRow(ConnectionStop(displayName: stop.getFullName(), stop: stop)) {
                            StopRow(stop: stop)
                        }
                    }
                }
                if !recents.isEmpty {
                    Section("Zuletzt") {
                        ForEach(recents, id: \.self) { destination in
                            destinationRow(destination) {
                                Label(destination.displayName, systemImage: destination.stop == nil ? "mappin.and.ellipse" : "clock.arrow.circlepath")
                            }
                        }
                    }
                }
            } else {
                Section("Haltestellen") {
                    ForEach(matchingStops) { stop in
                        destinationRow(ConnectionStop(displayName: stop.getFullName(), stop: stop)) {
                            StopRow(stop: stop)
                        }
                    }
                }
                if !addressSearch.results.isEmpty {
                    Section("Adressen und Orte") {
                        ForEach(addressSearch.results, id: \.self) { completion in
                            Button {
                                Task {
                                    if let destination = await addressSearch.resolve(completion) {
                                        choose(destination)
                                    }
                                }
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(completion.title)
                                    if !completion.subtitle.isEmpty {
                                        Text(completion.subtitle)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("Wohin?")
        .searchable(text: $searchText, prompt: "Haltestelle oder Adresse")
        .toolbar {
            // Suchfeld unten in der Leiste, wie in den Systemapps
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
        }
        .onChange(of: searchText) {
            addressSearch.update(query: searchText)
        }
        .onAppear {
            recents = RecentDestinations.load()
        }
    }

    private var favoriteStopList: [Stop] {
        favoriteStops.favorites.compactMap { stopID in
            stops.first { $0.stopID == stopID }
        }
    }

    private var matchingStops: [Stop] {
        Array(stops.filter { $0.getFullName().localizedCaseInsensitiveContains(searchText) }.prefix(15))
    }

    private func destinationRow(_ destination: ConnectionStop, @ViewBuilder label: () -> some View) -> some View {
        Button {
            choose(destination)
        } label: {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func choose(_ destination: ConnectionStop) {
        searchText = ""
        model.select(destination)
        recents = RecentDestinations.load()
    }
}

// MARK: - Ergebnis

private struct GoResultView: View {
    @Bindable var model: GoViewModel
    /// Wischposition des Pagers in Karten, nil bis zur ersten Meldung. Nur als Binding weitergereicht,
    /// damit beim Wischen nur Pager und Live-Section neu ausgewertet werden, nicht die ganze Liste.
    @State private var pagerPosition: CGFloat?

    /// Seitlicher Abstand der Sections. Fest vorgegeben statt System-Standard, damit die Übersichtskarten
    /// schon beim ersten Layout mit den Sections fluchten, ohne dass etwas gemessen werden muss.
    private let sectionMargin: CGFloat = 16

    var body: some View {
        content
            .navigationTitle(model.destination?.displayName ?? "")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) {
                        model.reset()
                    }
                }
                // Beim ersten Laden zeigt die Mitte den Fortschritt, danach dient der Knopf zum Aktualisieren
                if model.phase == .loaded {
                    ToolbarItem(placement: .primaryAction) {
                        if model.isRefreshing {
                            ProgressView()
                        } else {
                            Button("Aktualisieren", systemImage: "arrow.clockwise") {
                                Task {
                                    await model.plan(silent: true)
                                }
                            }
                        }
                    }
                }
            }
            .task(id: model.destination) {
                await model.plan()
                // Echtzeitdaten und Standort regelmäßig aktualisieren
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    if Task.isCancelled {
                        break
                    }
                    await model.plan(silent: true)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .locating:
            ProgressView("Standort wird bestimmt …")
        case .planning:
            ProgressView("Verbindung wird gesucht …")
        case .failed(let message):
            ContentUnavailableView {
                Label("Keine Verbindung", systemImage: "tram")
            } description: {
                Text(message)
            } actions: {
                Button("Erneut versuchen") {
                    Task {
                        await model.plan()
                    }
                }
            }
        case .loaded:
            if let route = model.selectedRoute {
                List {
                    Section {
                        LiveSection(routes: model.routes, selection: model.selectedIndex, position: $pagerPosition)
                            // gleicher Abstand oben und links, damit die Pill konzentrisch in der Section sitzt.
                            // Unten 0: Den Abstand zur Unterkante bringt der Satz selbst mit.
                            .listRowInsets(EdgeInsets(top: 11, leading: 11, bottom: 0, trailing: 11))
                    }
                    .listSectionMargins(.horizontal, sectionMargin)
                    Section {
                        RoutePager(
                            routes: model.routes,
                            selection: $model.selectedIndex,
                            position: $pagerPosition,
                            margin: sectionMargin
                        )
                        .listRowInsets(EdgeInsets())
                        // keine weiße Zeilenfläche: jede Übersicht bringt ihre eigene Karte mit
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    // volle Bildschirmbreite, damit die Karten beim Wischen nicht am Section-Rand abgeschnitten werden
                    .listSectionMargins(.horizontal, 0)
                    .listSectionSeparator(.hidden)
                    Section("Ablauf") {
                        RouteLegs(vm: TripSectionViewModel(route: route))
                    }
                    .listSectionMargins(.horizontal, sectionMargin)
                }
            }
        }
    }
}

// MARK: - Live

/// "Aufbrechen in X Min." für die gewählte Verbindung, darunter die Abfahrt des ersten Verkehrsmittels;
/// bei reinem Fußweg "Jederzeit aufbrechen" und "Du kannst laufen". Beides aktualisiert sich laufend.
/// Wie bei den Übersichten folgt die Höhe beim Wischen anteilig der Wischposition, sodass sich die Sections
/// darunter gleichmäßig mitbewegen.
private struct LiveSection: View {
    let routes: [Route]
    let selection: Int
    /// Wischposition des Pagers in Karten; nil, solange die Scroll-View noch keine gemeldet hat
    @Binding var position: CGFloat?

    /// Natürliche Höhe des Satzes jeder Verbindung
    @State private var sentenceHeights: [Int: CGFloat] = [:]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            if let route {
                let sentence = sentenceText(for: route, at: context.date)
                VStack(alignment: .leading, spacing: 0) {
                    header(for: route, at: context.date)
                    sentenceView(for: route, at: context.date)
                        .animation(.default, value: sentence)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // beim Wischen nur bis zur überblendeten Höhe sichtbar, wie bei den Übersichtskarten;
                        // vor der ersten Messung in natürlicher Höhe
                        .frame(height: sentenceAreaHeight, alignment: .top)
                        .clipped()
                        // alle Sätze unsichtbar in voller Breite messen, um zwischen zwei Verbindungen überzublenden
                        .background(alignment: .top) {
                            ForEach(routes.indices, id: \.self) { index in
                                sentenceView(for: routes[index], at: context.date)
                                    .hidden()
                                    .onGeometryChange(for: CGFloat.self) { proxy in
                                        proxy.size.height
                                    } action: { height in
                                        sentenceHeights[index] = height
                                    }
                            }
                        }
                }
                // oben verankert: Passt die Liste die Zeilenhöhe einen Moment später an als den Inhalt,
                // würde sie ihn mittig setzen, und Pill und Countdown wanderten kurz nach oben
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var route: Route? {
        routes.indices.contains(selection) ? routes[selection] : nil
    }

    private func header(for route: Route, at date: Date) -> some View {
        let minutes = minutesUntilLeaving(route, at: date)
        return HStack(spacing: 12) {
            LivePill()
            Text(titleText(for: route, at: date))
                .font(.title3.weight(.semibold))
                // Ziffern rollen in die Richtung, in die sich die Minuten ändern
                .contentTransition(.numericText(value: Double(minutes ?? 0)))
                .animation(.default, value: minutes)
        }
    }

    /// Wie die Zeile unter "Dauer" in der Übersicht
    private func sentenceView(for route: Route, at date: Date) -> some View {
        let rideMinutes = route.firstRide.flatMap { minutesUntilDeparture($0, at: date) }
        return Text(sentenceText(for: route, at: date))
            .font(.body)
            .foregroundStyle(.secondary)
            // wie beim Countdown rollen die Ziffern in die Richtung, in die sich die Minuten ändern
            .contentTransition(.numericText(value: Double(rideMinutes ?? 0)))
            // eingerückt wie eine normale Listenzeile, nicht so knapp wie die Pill. Unten samt Abstand zur
            // Section-Kante, damit der Satz beim Aufdecken genau an der Kante abgeschnitten wird.
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .padding(.bottom, 14)
            // natürliche Höhe behalten und abgeschnitten werden, statt mit "…" gekürzt
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Höhe des Satzbereichs zwischen den beiden Verbindungen, zwischen denen gerade gewischt wird
    private var sentenceAreaHeight: CGFloat? {
        interpolatedHeight(at: position ?? CGFloat(selection), count: routes.count) { sentenceHeights[$0] }
    }

    private func minutesUntilLeaving(_ route: Route, at date: Date) -> Int? {
        route.leaveTime.map { Int($0.timeIntervalSince(date) / 60) }
    }

    private func minutesUntilDeparture(_ ride: PartialRoute, at date: Date) -> Int? {
        ride.getStartTime().map { Int($0.timeIntervalSince(date) / 60) }
    }

    /// "Jetzt aufbrechen", "Aufbrechen in 5 Min.", ab einer Stunde wie der Satz darunter die Uhrzeit
    private func titleText(for route: Route, at date: Date) -> String {
        if route.isWalkOnly {
            return "Jederzeit aufbrechen"
        }
        guard let leaveTime = route.leaveTime else { return "–" }
        let minutes = Int(leaveTime.timeIntervalSince(date) / 60)
        switch minutes {
        case ..<1:
            return "Jetzt aufbrechen"
        case ..<60:
            return "Aufbrechen in \(RouteOverview.durationText(minutes: minutes))"
        default:
            return "Um \(leaveTime.formatted(date: .omitted, time: .shortened)) aufbrechen"
        }
    }

    private func sentenceText(for route: Route, at date: Date) -> String {
        guard let ride = route.firstRide else { return "Du kannst laufen :)" }
        return rideText(for: ride, at: date)
    }

    /// "Die Buslinie 68 fährt in 5 Minuten an der Haltestelle Klosterteichplatz ab."
    private func rideText(for ride: PartialRoute, at date: Date) -> String {
        var line = TransitMode(motType: ride.Mot.type).lineTitle
        if let name = ride.Mot.Name {
            line += " \(name)"
        }
        var text = "Die \(line) fährt"
        if let departure = ride.getStartTime() {
            text += " \(departureTimeText(departure, at: date))"
        }
        if let stop = ride.RegularStops?.first?.Name {
            text += " an der Haltestelle \(stop)"
        }
        return text + " ab."
    }

    /// "jetzt", "in 1 Minute", "in 5 Minuten", ab einer Stunde die Uhrzeit
    private func departureTimeText(_ departure: Date, at date: Date) -> String {
        let minutes = Int(departure.timeIntervalSince(date) / 60)
        switch minutes {
        case ..<1:
            return "jetzt"
        case 1:
            return "in 1 Minute"
        case ..<60:
            return "in \(minutes) Minuten"
        default:
            return "um \(departure.formatted(date: .omitted, time: .shortened))"
        }
    }
}

/// Höhe beim Wischen zwischen zwei Karten, anteilig zwischen den Höhen der beiden beteiligten Karten.
/// Über den Rand hinaus gezogen (Gummiband) gilt die Höhe der Randkarte.
private func interpolatedHeight(at position: CGFloat, count: Int, height: (Int) -> CGFloat?) -> CGFloat? {
    guard count > 0 else { return nil }
    let clamped = min(max(position, 0), CGFloat(count - 1))
    let lower = Int(clamped)
    let upper = min(lower + 1, count - 1)
    guard let lowerHeight = height(lower), let upperHeight = height(upper) else { return nil }
    return lowerHeight + (upperHeight - lowerHeight) * (clamped - CGFloat(lower))
}

// MARK: - Übersichten zum Wischen

/// Übersichten aller Verbindungen zum seitlichen Wischen, wie in Apple Karten.
/// Gewischt wird mit dem Standard-Paging. Die Wischposition wird nur gelesen: Daraus ergeben sich die Auswahl
/// und die Höhe, die anteilig zwischen den beiden beteiligten Karten liegt, sodass sich die Sections darunter
/// gleichmäßig mitbewegen. Der Scroll-Inhalt selbst behält dabei immer dieselbe Größe.
///
/// Die Scroll-View ist genau eine Karte plus Abstand breit und fluchtet mit den übrigen Sections. So rastet
/// das Paging mit nur 8 pt Abstand zwischen den Karten ein; die Nachbarn bleiben bis zum Bildschirmrand sichtbar.
private struct RoutePager: View {
    let routes: [Route]
    @Binding var selection: Int
    /// Wischposition in Seiten: 1,4 heißt 40 % des Wegs von Karte 1 zu Karte 2. Geteilt mit der Live-Section;
    /// nil, solange die Scroll-View noch keine gemeldet hat
    @Binding var position: CGFloat?
    /// Seitlicher Abstand der übrigen Sections; die Karten fluchten mit ihnen
    let margin: CGFloat

    /// Natürliche Höhe jeder Karte
    @State private var cardHeights: [Int: CGFloat] = [:]
    @State private var phase: ScrollPhase = .idle

    private let cornerRadius: CGFloat = 26
    /// Abstand zwischen zwei Karten
    private let spacing: CGFloat = 8

    var body: some View {
        VStack(spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    // kein LazyHStack: jede Karte wird gemessen, auch die gerade nicht sichtbaren
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(routes.indices, id: \.self) { index in
                            page(at: index)
                        }
                    }
                }
                // eine Seite: Karte so breit wie die übrigen Sections plus Abstand zur nächsten
                .containerRelativeFrame(.horizontal) { width, _ in
                    width - 2 * margin + spacing
                }
                .frame(height: tallestHeight)
                // Nachbarkarten auch außerhalb der Scroll-View zeigen, bis zum Bildschirmrand
                .scrollClipDisabled()
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                // beim Öffnen direkt auf der gewählten Karte stehen, ohne nachträglichen Sprung
                .defaultScrollAnchor(selectedPageAnchor, for: .initialOffset)
                // nur lesen: aus der Wischposition ergeben sich Höhe und Auswahl, das Scrollen selbst bleibt unberührt
                .onScrollGeometryChange(for: CGFloat?.self) { geometry in
                    guard geometry.containerSize.width > 0 else { return nil }
                    return (geometry.contentOffset.x + geometry.contentInsets.leading) / geometry.containerSize.width
                } action: { _, newPosition in
                    if let newPosition {
                        position = newPosition
                    }
                }
                .onScrollPhaseChange { oldPhase, newPhase in
                    phase = newPhase
                    // Absicherung, falls der letzte Seitenwechsel erst beim Einrasten ankommt
                    if newPhase == .idle, oldPhase != .idle, selection != currentPage {
                        selection = currentPage
                    }
                }
                // ab halber Strecke wechseln Countdown und Ablauf mit, auch während die Karte noch ausläuft
                .onChange(of: currentPage) {
                    if phase == .interacting || phase == .decelerating, selection != currentPage {
                        selection = currentPage
                    }
                }
                // nach dem Aktualisieren kann die gewählte Verbindung an anderer Stelle stehen;
                // die Scroll-View wird nur im Ruhezustand bewegt, nie während des Wischens
                .onChange(of: selection) {
                    if phase == .idle, selection != currentPage {
                        proxy.scrollTo(selection)
                    }
                }
            }
            .padding(.leading, margin)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Zeile so hoch wie die Karte unter dem Finger; die Scroll-View ragt darunter unsichtbar hinaus,
            // weil die Karten dort maskiert sind
            .frame(height: height, alignment: .top)

            if routes.count > 1 {
                pageIndicator
            }
        }
    }

    /// Eine Seite ist eine Karte plus Abstand zur nächsten
    private func page(at index: Int) -> some View {
        RouteOverview(route: routes[index])
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            // natürliche Höhe messen, unabhängig von der Höhe des Wisch-Bereichs
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.height
            } action: { height in
                cardHeights[index] = height
            }
            // Layout immer so hoch wie die höchste Karte, damit sich der Scroll-Inhalt beim Wischen nicht ändert
            .frame(height: tallestHeight, alignment: .top)
            // Inhalt sichtbar nur bis zur aktuellen Höhe: Längere Karten werden an der Kartenkante abgeschnitten,
            // bis sie ganz hereingewischt sind
            .mask(alignment: .top) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .frame(height: height)
            }
            // Glasfläche in derselben Form und Höhe; kürzere Karten wachsen nach unten. Erst nach der Maske,
            // damit das Glas nicht mitmaskiert wird und den Hintergrund dahinter weiter sauber spiegelt.
            .background(alignment: .top) {
                Color.clear
                    .frame(height: height)
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
            .padding(.trailing, spacing)
            .containerRelativeFrame(.horizontal)
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(routes.indices, id: \.self) { index in
                Circle()
                    .fill(index == selection ? Color.primary : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
            }
        }
        .animation(.default, value: selection)
        .accessibilityHidden(true)
    }

    /// Bis die Scroll-View ihre Position meldet, steht sie auf der gewählten Karte
    private var currentPosition: CGFloat {
        position ?? CGFloat(selection)
    }

    /// Karte, die gerade überwiegend zu sehen ist
    private var currentPage: Int {
        min(max(Int(currentPosition.rounded()), 0), max(routes.count - 1, 0))
    }

    /// Ankerpunkt der gewählten Karte: Alle Seiten sind gleich breit, Karte k von n liegt also
    /// bei k / (n − 1) des Scrollbereichs
    private var selectedPageAnchor: UnitPoint {
        guard routes.count > 1 else { return .leading }
        return UnitPoint(x: CGFloat(selection) / CGFloat(routes.count - 1), y: 0.5)
    }

    /// Höhe zwischen den beiden Karten, zwischen denen gerade gewischt wird, anteilig zum Fortschritt
    private var height: CGFloat? {
        interpolatedHeight(at: currentPosition, count: routes.count) { cardHeights[$0] }
    }

    /// Höhe der höchsten Karte; so groß ist der Inhalt der Scroll-View immer
    private var tallestHeight: CGFloat? {
        routes.indices.compactMap { cardHeights[$0] }.max()
    }
}

/// Hinweis "Live": längliche, leicht grüne Kapsel mit konzentrischem grünen Punkt links
private struct LivePill: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false
    private let height: CGFloat = 30
    private let dotSize: CGFloat = 12

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                // Radar-Puls: Ring wächst vom Punkt aus und verblasst, in Endlosschleife
                if !reduceMotion {
                    Circle()
                        .fill(.green)
                        .scaleEffect(isPulsing ? 1.8 : 1)
                        .opacity(isPulsing ? 0 : 0.6)
                        .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false), value: isPulsing)
                }
                Circle()
                    .fill(.green)
            }
            .frame(width: dotSize, height: dotSize)
            .onAppear {
                isPulsing = true
            }
            Text("Live")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.green)
        }
        // Punkt sitzt im Mittelpunkt der linken Rundung: links derselbe Abstand wie oben und unten
        .padding(.leading, (height - dotSize) / 2)
        .padding(.trailing, 10)
        .frame(height: height)
        .background(.green.opacity(0.15), in: Capsule())
    }
}

#Preview("Zielauswahl") {
    GoView()
        .environmentObject(FavoriteStop())
}

#Preview("Verbindung") {
    @Previewable @State var model = GoViewModel.preview
    NavigationStack {
        GoResultView(model: model)
    }
    .environmentObject(FavoriteStop())
}
