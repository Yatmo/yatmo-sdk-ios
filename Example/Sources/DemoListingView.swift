import SwiftUI
import YatmoSDK

/// Marketing screen: a listing page of a fictional real-estate app ("Nestly") with the Yatmo map and data.
/// Launched with `simctl launch <sim> com.yatmo.test.ios -demo`. Data on screen is real (enrichment API).
struct DemoListingView: View {
    @State private var nearby: [YatmoEnrichedCategory] = []

    private let accent = Color(red: 0.26, green: 0.55, blue: 1.0)

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    listing
                    Text("Le quartier")
                        .font(.system(size: 20, weight: .bold))
                        .padding(.horizontal, 20)
                        .padding(.top, 22)
                        .padding(.bottom, 10)
                        .id("quartier")
                    YatmoMap(yatmo: yatmo,
                             latitude: testLatitude,
                             longitude: testLongitude,
                             zoom: 15,
                             style: .liberty)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal, 20)
                    nearbyList
                    Spacer(minLength: 24)
                }
            }
            .clipped() // keep the content out of the status bar area when scrolled
            .onAppear {
                if CommandLine.arguments.contains("-scrolled") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { proxy.scrollTo("price", anchor: .top) }
                }
            }
            }
            tabBar
        }
        .background(Color.white)
        .task {
            if let e = try? await yatmo.client.enrichment(latitude: testLatitude, longitude: testLongitude) {
                let wanted = ["Children.PreSchool", "Transports.Metros", "Shopping.Hypermarket", "Transports.Trains"]
                nearby = wanted.compactMap { key in e.categories.first { $0.key == key && $0.nearest != nil } }
                if nearby.count < 3 { nearby = Array(e.categories.filter { $0.nearest != nil }.prefix(4)) }
            }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
            Spacer()
            Text("Nestly").font(.system(size: 20, weight: .heavy)).foregroundColor(accent)
            Spacer()
            Image(systemName: "heart").font(.system(size: 18, weight: .semibold))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var listing: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(colors: [Color(red: 0.93, green: 0.90, blue: 0.85), Color(red: 0.78, green: 0.72, blue: 0.64)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 150)
                Image(systemName: "building.2.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("Nouveau")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(accent).foregroundColor(.white)
                    .clipShape(Capsule())
                    .padding(12)
            }
            Text("425 000 €").font(.system(size: 26, weight: .bold)).padding(.top, 6).id("price")
            Text("Appartement 2 chambres, Dansaert").font(.system(size: 17, weight: .semibold))
            Text("Rue du Rempart des Moines, 1000 Bruxelles").font(.system(size: 14)).foregroundColor(.secondary)
            HStack(spacing: 14) {
                Label("95 m²", systemImage: "square.split.bottomrightquarter")
                Label("2 ch.", systemImage: "bed.double")
                Label("Terrasse", systemImage: "sun.max")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
    }

    private var nearbyList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("À proximité").font(.system(size: 20, weight: .bold)).padding(.top, 22)
            ForEach(nearby, id: \.id) { category in
                HStack(spacing: 12) {
                    Image(systemName: icon(for: category.key))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(accent)
                        .frame(width: 38, height: 38)
                        .background(accent.opacity(0.12))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.nearest?.name ?? "").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Text(category.label).font(.system(size: 13)).foregroundColor(.secondary)
                    }
                    Spacer()
                    if let minutes = category.nearest?.walking?.durationMinutes {
                        Label("\(minutes) min", systemImage: "figure.walk")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var tabBar: some View {
        HStack {
            tab("magnifyingglass", "Recherche", selected: false)
            tab("house.fill", "Biens", selected: true)
            tab("heart", "Favoris", selected: false)
            tab("person", "Profil", selected: false)
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Color(white: 0.98))
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(Color(white: 0.85)), alignment: .top)
    }

    private func tab(_ icon: String, _ label: String, selected: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 20))
            Text(label).font(.system(size: 11))
        }
        .foregroundColor(selected ? accent : .secondary)
        .frame(maxWidth: .infinity)
    }

    private func icon(for key: String) -> String {
        if key.contains("School") { return "graduationcap.fill" }
        if key.contains("Metro") || key.contains("Train") || key.contains("Tram") || key.contains("Bus") { return "tram.fill" }
        if key.contains("market") || key.contains("Shop") { return "cart.fill" }
        return "mappin.circle.fill"
    }
}
