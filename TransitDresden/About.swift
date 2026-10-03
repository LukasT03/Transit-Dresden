//
//  About.swift
//  TransitDresden
//
//  Created by Peter Lohse on 14.05.23.
//

import SwiftUI

struct About: View {
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("App-Information")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unbekannt") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unbekannt"))")
                    }.accessibilityElement(children: .combine)
                }

                Section(header: Text("Projekt")) {
                    Link(destination: URL(string: "https://github.com/LukasT03/Transit-Dresden")!) {
                        HStack {
                            Image("GitHubIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .offset(x: 1)
                            Text(verbatim: "GitHub")
                                .offset(x: -1)

                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("GitHub Repository mit Quellcode zur App aufrufen")
                    }
                }

                Section(header: Text("Lizenz"), footer: Text("Transit Dresden ist eine veränderte Version des Haltestellenmonitor Dresden von HanashiDev und steht unter der GNU GPL v3.")) {
                    Link(destination: URL(string: "https://github.com/HanashiDev/Haltestellenmonitor-v3")!) {
                        Text(verbatim: "Original-Projekt auf GitHub")
                    }
                }
            }
            .navigationTitle("Über")
        }
    }
}

struct Contact_Previews: PreviewProvider {
    static var previews: some View {
        About()
    }
}
