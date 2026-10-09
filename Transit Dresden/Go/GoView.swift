//
//  GoView.swift
//  Transit Dresden
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
    @State private var showsResult = false

    var body: some View {
        NavigationStack {
            destinationPicker
        }
        // Beim Schließen wird nichts zurückgesetzt, sonst zeigte das Sheet beim Hinausgleiten schon den leeren
        // Ladezustand; select(_:) setzt beim nächsten Ziel ohnehin alles neu, bevor es wieder aufgeht
        .sheet(isPresented: $showsResult) {
            NavigationStack {
                GoResultView(model: model)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
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
                        destinationRow(ConnectionStop(displayName: stop.name, stop: stop)) {
                            StopRow(stop: stop, showsPlace: false)
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
                        // Titel im Ergebnis nur der Name; der Ort steht hier darunter, damit man gleichnamige
                        // Haltestellen (z. B. "Bahnhof") unterscheiden kann
                        destinationRow(ConnectionStop(displayName: stop.name, stop: stop)) {
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
        showsResult = true
        recents = RecentDestinations.load()
    }
}

// MARK: - Ergebnis

private struct GoResultView: View {
    @Bindable var model: GoViewModel
    @Environment(\.dismiss) private var dismiss
    /// Wischposition des Pagers in Karten, nil bis zur ersten Meldung. Nur als Binding weitergereicht,
    /// damit beim Wischen nur Pager und Live-Section neu ausgewertet werden, nicht die ganze Liste.
    @State private var pagerPosition: CGFloat?
    /// Scroll-Phase des Pagers; die Knöpfe unten blättern nur im Ruhezustand. Nur im Knopf gelesen, damit ihr
    /// Wechsel die Ansicht nicht neu auswertet.
    @State private var pagerPhase: ScrollPhase = .idle
    /// Lade-Overlay sichtbar; folgt isLoading, aber animiert (siehe loadingOverlay)
    @State private var showsLoadingOverlay = true
    /// Knöpfe unten sichtbar; sie erscheinen erst, wenn das Lade-Overlay ausgeblendet ist
    @State private var showsBottomBar = false

    /// Seitlicher Abstand der Sections. Fest vorgegeben statt System-Standard, damit die Übersichtskarten
    /// schon beim ersten Layout mit den Sections fluchten, ohne dass etwas gemessen werden muss.
    private let sectionMargin: CGFloat = 16

    var body: some View {
        content
            .overlay {
                loadingOverlay
            }
            .navigationTitle(model.destination?.displayName ?? "")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
            }
            .task(id: model.destination) {
                await model.plan()
                // Echtzeitdaten und Standort selbstständig aktualisieren; ohne Knopf dafür etwas öfter
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    if Task.isCancelled {
                        break
                    }
                    await model.plan(silent: true)
                }
            }
    }

    /// Deckt beim Laden alles mit Spinner ab und blendet aus, sobald Ergebnis oder Fehler da sind.
    /// Nur das Overlay wird animiert, der Inhalt darunter erscheint einfach.
    private var loadingOverlay: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            // Der Spinner ist eine UIKit-Ansicht und finge beim Ausblenden von vorn an, weil SwiftUI ihn dafür
            // umhängt. Deshalb verschwindet er sofort, nur die Fläche blendet aus.
            if isLoading {
                ProgressView()
            }
        }
        .opacity(showsLoadingOverlay ? 1 : 0)
        // ausgeblendet keine Berührungen abfangen
        .allowsHitTesting(showsLoadingOverlay)
        // Eigener Zustand mit explizitem withAnimation in einem eigenen Update: Hinge die Animation direkt an
        // der Phase, ginge sie im selben Update unter, in dem die Liste entsteht und sich die Leiste ändert,
        // und das Overlay verschwände abrupt. Initial auch, falls schon beim Öffnen ein Ergebnis da ist.
        .onChange(of: isLoading, initial: true) {
            withAnimation {
                showsLoadingOverlay = isLoading
            }
        }
        // die Knöpfe unten erst kurz nach dem Ausblenden, auf der fertigen Ansicht; beim erneuten Laden gleich weg
        .task(id: isLoading) {
            guard !isLoading else {
                showsBottomBar = false
                return
            }
            try? await Task.sleep(for: .seconds(0.35))
            guard !Task.isCancelled else { return }
            withAnimation {
                showsBottomBar = true
            }
        }
    }

    private var isLoading: Bool {
        switch model.phase {
        case .idle, .locating, .planning: true
        case .loaded, .failed: false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .locating, .planning:
            // verdeckt vom Lade-Overlay. Bewusst eine echte Fläche statt EmptyView: An einer leeren View
            // hingen Overlay und .task ins Leere, es würde weder etwas angezeigt noch geladen.
            Color.clear
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
                            phase: $pagerPhase,
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
                    Section() {
                        RouteLegs(
                            route: route,
                            destinationName: model.destination?.displayName ?? "Ziel",
                            platformStops: model.platformStops,
                            nearbyStops: model.nearbyStops
                        )
                    }
                    .listSectionMargins(.horizontal, sectionMargin)
                }
                // die Haltestellen im Ablauf sind eigene Zeilen, niedriger als die Standard-Mindesthöhe
                .environment(\.defaultMinListRowHeight, 0)
                .scrollIndicators(.hidden)
                // Ohne Kanteneffekt hinter der unteren Leiste: Die Liste scrollt einfach darunter durch
                .scrollEdgeEffectHidden(true, for: .bottom)
                // Untere Leiste: Das System setzt die Knöpfe konzentrisch in die Rundung des Displays, die Blätter-
                // Knöpfe in die Ecken. Gibt es nur eine Verbindung, steht "Verbindung nutzen" allein in der Mitte.
                .toolbar {
                    if model.routes.count > 1 {
                        ToolbarItem(placement: .bottomBar) {
                            pageButton("Vorherige Verbindung", systemImage: "chevron.left", step: -1)
                        }
                    }
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            // TODO: gewählte Verbindung einmalig bis zur Ankunft begleiten; vorerst nur die Optik
                        } label: {
                            Text("Verbindung nutzen")
                                // dunkel statt weiß: Weiß auf dem hellen Gelb der Akzentfarbe ist kaum lesbar
                                .foregroundStyle(.black)
                        }
                        .buttonStyle(.glassProminent)
                    }
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    if model.routes.count > 1 {
                        ToolbarItem(placement: .bottomBar) {
                            pageButton("Nächste Verbindung", systemImage: "chevron.right", step: 1)
                        }
                    }
                }
                // Erst nach dem Lade-Overlay, siehe showsBottomBar. Die Leiste wird nur versteckt statt ihre Knöpfe
                // einzufügen: Eingefügte Knöpfe ploppen auf, eine animiert eingeblendete Leiste gleitet herein.
                .toolbarVisibility(showsBottomBar ? .visible : .hidden, for: .bottomBar)
            }
        }
    }

    /// Knopf zum Blättern zwischen den Verbindungen; an der ersten bzw. letzten ausgegraut
    private func pageButton(_ title: String, systemImage: String, step: Int) -> some View {
        let target = model.selectedIndex + step
        return Button(title, systemImage: systemImage) {
            // erst wieder, wenn die Karte steht: Schnelles Tippen brächte Scrollen und Animationen durcheinander
            guard pagerPhase == .idle else { return }
            // Die Auswahl wechselt sofort, der Pager gleitet hinterher. Ohne Animation: Eine animierte Auswahl ließe
            // die Liste den Ablauf animiert tauschen und dabei die Höhenänderungen der oberen Sections zurückhalten.
            model.selectedIndex = target
        }
        .disabled(!model.routes.indices.contains(target))
    }
}

// MARK: - Live

/// "In X Min. losgehen" für die gewählte Verbindung, knapp "Jetzt losrennen", an der Haltestelle "In X Min. einsteigen", darunter die
/// Abfahrt des ersten Verkehrsmittels; bei reinem Fußweg "Jederzeit losgehen" und "Du kannst laufen".
/// Beides aktualisiert sich laufend.
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
                VStack(alignment: .leading, spacing: 0) {
                    header(for: route, at: context.date)
                    sentenceView(for: route, at: context.date)
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
            title(for: route, at: date)
                .font(.title3.weight(.semibold))
                // Ziffern rollen in die Richtung, in die sich die Minuten ändern. Ausgelöst vom Text statt von den
                // Minuten: Beim Wechsel von "Jetzt losgehen" zu "Jetzt losrennen" bleiben die Minuten bei 0.
                .contentTransition(.numericText(value: Double(minutes ?? 0)))
                .animation(.default, value: titleText(for: route, at: date))
        }
    }

    /// Wie die Zeile unter der Abfahrt in der Übersicht
    private func sentenceView(for route: Route, at date: Date) -> some View {
        Text(sentenceText(for: route, at: date))
            .font(.body)
            .foregroundStyle(.secondary)
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

    /// Beim Losrennen mit Läufer dahinter; als Symbol im Text richtet er sich nach dessen Schrift
    private func title(for route: Route, at date: Date) -> Text {
        let text = titleText(for: route, at: date)
        guard route.needsRunning(at: date) else { return Text(text) }
        return Text("\(text) \(Image(systemName: "figure.run"))")
    }

    /// "Jetzt losgehen", "In 5 Min. losgehen", ab einer Stunde wie der Satz darunter die Uhrzeit; immer erst die Zeit,
    /// dann das Verb. Steht man schon an der Haltestelle, heißt es "einsteigen" statt "losgehen".
    /// Ist die Losgehzeit vorbei, die Verbindung aber noch zu schaffen: "Jetzt losrennen".
    private func titleText(for route: Route, at date: Date) -> String {
        if route.isWalkOnly {
            return "Jederzeit losgehen"
        }
        if route.needsRunning(at: date) {
            return "Jetzt losrennen"
        }
        guard let leaveTime = route.leaveTime else { return "–" }
        let minutes = Int(leaveTime.timeIntervalSince(date) / 60)
        let verb = route.startsAtStop ? "einsteigen" : "losgehen"
        switch minutes {
        case ..<1:
            return "Jetzt \(verb)"
        case ..<60:
            return "In \(RouteOverview.durationText(minutes: minutes)) \(verb)"
        default:
            return "Um \(leaveTime.formatted(date: .omitted, time: .shortened)) \(verb)"
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
    /// Scroll-Phase; geteilt, damit die Knöpfe unten nur blättern, wenn die Karte steht
    @Binding var phase: ScrollPhase
    /// Seitlicher Abstand der übrigen Sections; die Karten fluchten mit ihnen
    let margin: CGFloat

    /// Natürliche Höhe jeder Karte
    @State private var cardHeights: [Int: CGFloat] = [:]
    @State private var scrollPosition = ScrollPosition(idType: Int.self)

    private let cornerRadius: CGFloat = 26
    /// Abstand zwischen zwei Karten
    private let spacing: CGFloat = 8

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal) {
                // kein LazyHStack: jede Karte wird gemessen, auch die gerade nicht sichtbaren
                HStack(alignment: .top, spacing: 0) {
                    ForEach(routes.indices, id: \.self) { index in
                        page(at: index)
                    }
                }
                // nachgeladene Karten blenden ein, statt am Rand aufzutauchen
                .animation(.default, value: routes.count)
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
            .scrollPosition($scrollPosition)
            // nur lesen: aus der Wischposition ergeben sich Höhe und Auswahl, das Scrollen selbst bleibt unberührt.
            // Auch beim animierten Blättern meldet die Scroll-View jeden Zwischenschritt.
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
            // Auswahl von außen, über die Knöpfe unten oder nach dem Aktualisieren: Die Karte gleitet hinterher,
            // nur im Ruhezustand, nie während des Wischens. Zügiger als die Standardanimation und ohne Nachfedern,
            // damit die Karte sauber einrastet.
            .onChange(of: selection) {
                if phase == .idle, selection != currentPage {
                    withAnimation(.smooth(duration: 0.2)) {
                        scrollPosition.scrollTo(id: selection)
                    }
                }
            }
            .padding(.leading, margin)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Zeile so hoch wie die Karte unter dem Finger; die Scroll-View ragt darunter unsichtbar hinaus,
            // weil die Karten dort maskiert sind
            .frame(height: height, alignment: .top)

            // auch bei nur einer Verbindung Platz halten: Kommen weitere nachgeladen dazu, rutscht darunter nichts
            pageIndicator
                .opacity(routes.count > 1 ? 1 : 0)
                .animation(.default, value: routes.count)
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

#Preview() {
    @Previewable @State var model = GoViewModel.preview
    NavigationStack {
        GoResultView(model: model)
    }
    .environmentObject(FavoriteStop())
}
