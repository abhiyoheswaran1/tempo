import SwiftUI
import TempoCore
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.json] }
  var data: Data
  init(data: Data = Data()) { self.data = data }
  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else { throw StoreError.invalidArchive }
    self.data = data
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}
struct SettingsView: View {
  @Environment(AppModel.self) var model
  @Environment(\.dismiss) var dismiss
  @State private var export = false
  @State private var importing = false
  @State private var document = BackupDocument()
  var body: some View {
    @Bindable var m = model
    List {
      Section("Bands") {
        NavigationLink("Manage and reconnect bands") { DevicesView() }
        Picker(
          "Source mode",
          selection: Binding(
            get: { model.selector.preference },
            set: { p in model.mutate { try await model.setPreference(p) } })
        ) {
          Text("Automatic").tag(SourcePreference.automatic)
          Text("Prefer Whoop 4").tag(SourcePreference.prefer4)
          Text("Prefer Whoop 5").tag(SourcePreference.prefer5)
        }
        if model.selector.overrideID != nil {
          Button("Return to Automatic") {
            model.mutate { try await model.setPreference(.automatic) }
          }
        }
        NavigationLink("Collection health") { CollectionHealthView() }
      }
      Section("Private iCloud") {
        Toggle("Sync and restore history", isOn: $m.syncEnabled).disabled(model.demo).onChange(
          of: model.syncEnabled
        ) { _, enabled in
          model.mutate { try await model.persistPreferences() }
          if enabled { Task { await model.sync() } }
        }
        Text(model.cloud?.status ?? "Off · local collection works without iCloud").font(
          .subheadline)
        if let cloud = model.cloud {
          if let date = cloud.lastSuccess {
            LabeledContent("Last success", value: date.formatted())
          }
          LabeledContent("Pending uploads", value: String(cloud.pendingUploads))
          LabeledContent("Restored records", value: String(cloud.restoredRecords))
          if let error = cloud.errorMessage { Text(error).foregroundStyle(.orange) }
          Button("Retry sync") { Task { await model.sync(forceRetry: true) } }.disabled(cloud.busy)
        }
        Text(
          "On a new phone, enable sync using the same Apple account, then explicitly reconnect each physical band. Bluetooth bonds are not restored."
        ).font(.caption).foregroundStyle(.secondary)
      }
      if !model.conflictEntities.isEmpty {
        Section("Concurrent edits") {
          ForEach(model.conflictEntities, id: \.self) { id in
            NavigationLink("Resolve \(id.uuidString.prefix(8))") { ConflictView(entityID: id) }
          }
        }
      }
      Section("Health and privacy") {
        NavigationLink("Apple Health permissions") { HealthSettingsView() }.disabled(model.demo)
        Toggle("Hide sensitive widget details", isOn: $m.hideWidgetDetails).onChange(
          of: model.hideWidgetDetails
        ) { _, _ in model.mutate { try await model.persistPreferences() } }
        Text(
          "No Whoop account, custom server, analytics SDK or routine health-payload logging. CloudKit uses encrypted payload fields in your private database; this app does not assert end-to-end encryption."
        ).font(.caption).foregroundStyle(.secondary)
      }
      Section("Analytics") {
        Stepper(
          "Maximum heart rate: \(Int(model.maxHeartRate)) bpm", value: $m.maxHeartRate,
          in: 100...240, step: 1
        ).onChange(of: model.maxHeartRate) { _, _ in
          model.mutate { try await model.persistPreferences() }
        }
        Text(
          "Zone load uses this personal setting. The initial 190 bpm value is a configurable assumption, not a measured maximum."
        ).font(.caption).foregroundStyle(.secondary)
        NavigationLink("Readiness methodology") { ReadinessDetailView() }
      }
      Section("Independent backup") {
        Button("Export validated history") {
          Task {
            do {
              guard let store = model.store else { return }
              document = BackupDocument(data: try JSONEncoder().encode(await store.exportArchive()))
              export = true
            } catch { model.errorMessage = error.localizedDescription }
          }
        }.disabled(model.demo)
        Button("Restore backup") { importing = true }.disabled(model.demo)
        Text(
          "Exports are plaintext health data. Store them somewhere you trust. A checksum checks integrity, not encryption or authenticity."
        ).font(.caption).foregroundStyle(.secondary)
      }
      Section("Explore") {
        Toggle(
          "Simulator demo · synthetic data",
          isOn: Binding(
            get: { model.demo }, set: { enabled in Task { await model.setDemo(enabled) } }))
        NavigationLink("Journal history") {
          List(model.journals) { entry in
            NavigationLink {
              JournalEditor(entry: entry)
            } label: {
              VStack(alignment: .leading) {
                Text(entry.date, format: .dateTime.month().day())
                Text(entry.note.isEmpty ? "Optional daily check-in" : entry.note).font(.caption)
              }
            }
          }.navigationTitle("Journal")
        }
      }
    }.navigationTitle("Settings").toolbar {
      ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
    }
    .fileExporter(
      isPresented: $export, document: document, contentType: .json,
      defaultFilename: "Tempo-\(Date().formatted(.iso8601.year().month().day()))"
    ) { result in
      if case .failure(let error) = result { model.errorMessage = error.localizedDescription }
    }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
      Task {
        do {
          let url = try result.get()
          let access = url.startAccessingSecurityScopedResource()
          defer { if access { url.stopAccessingSecurityScopedResource() } }
          let values = try url.resourceValues(forKeys: [.fileSizeKey])
          guard (values.fileSize ?? 0) <= 350 * 1024 * 1024 else { throw StoreError.invalidArchive }
          let archive = try JSONDecoder().decode(BackupArchive.self, from: Data(contentsOf: url))
          try await model.store?.importArchive(archive)
          try await model.load()
        } catch { model.errorMessage = "Restore rejected: \(error.localizedDescription)" }
      }
    }
  }
}
struct DevicesView: View {
  @Environment(AppModel.self) var model
  @State private var generation: DeviceGeneration = .whoop4
  @State private var matching: UUID?
  var body: some View {
    List {
      Section("Registered bands") {
        ForEach(model.devices) { device in
          NavigationLink {
            DeviceDetailView(device: device)
          } label: {
            VStack(alignment: .leading) {
              Text(device.name).font(.headline)
              Text(
                "\(device.generation.rawValue) · \(model.bluetooth.connected.contains(device.id) ? "Connected":"Registered")"
              ).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
        if model.devices.isEmpty { Text("Register your bands once; keep one continuous history.") }
      }
      Section("Discover or reconnect") {
        Picker("Generation", selection: $generation) {
          Text("Whoop 4").tag(DeviceGeneration.whoop4)
          Text("Whoop 5").tag(DeviceGeneration.whoop5)
        }
        Picker("Match to registry", selection: $matching) {
          Text("Register a new band").tag(UUID?.none)
          ForEach(model.devices) { Text("Reconnect \($0.name)").tag(UUID?.some($0.id)) }
        }
        Button("Scan for my bands") { model.bluetooth.scan() }.disabled(model.demo)
        Text(
          "Use pairing / heart-rate broadcast mode where supported. Confirm the physical band before matching it. A nearby name or signal strength does not prove identity or wear."
        ).font(.caption).foregroundStyle(.secondary)
        ForEach(model.bluetooth.discovered) { d in
          Button {
            model.mutate {
              try await model.register(
                d, generation: d.generation ?? generation, existing: matching)
            }
          } label: {
            HStack {
              Text(d.name)
              Spacer()
              Text(d.generation?.rawValue ?? "Confirm generation").font(.caption)
            }
          }
        }
        Text(model.bluetooth.status).font(.caption)
      }
    }.navigationTitle("Your bands").onDisappear { model.bluetooth.stopScan() }
  }
}
struct DeviceDetailView: View {
  @Environment(AppModel.self) var model
  let device: RegisteredDevice
  @State private var name = ""
  var body: some View {
    List {
      Section("Identity") {
        TextField("Friendly name", text: $name)
        Button("Save name") {
          model.mutate {
            var d = device
            d.name = name
            try await model.save(d, kind: "device")
          }
        }
        Text("App identity: \(device.id.uuidString)").font(.caption).textSelection(.enabled)
        LabeledContent("Firmware", value: device.firmware ?? "Not readable yet")
        LabeledContent(
          "Hardware identifier",
          value: device.hardwareIdentityHash == nil ? "Unresolved" : "Serial hash retained")
      }
      Section("Connection") {
        Button("Connect this band") { model.bluetooth.connect(deviceID: device.id) }
        Button("Use temporarily") { model.override(device.id) }
        Text(
          "Only one band connection is maintained until concurrent behavior is physically validated. Automatic wear-based switching cannot be promised from an unconnected band."
        ).font(.caption).foregroundStyle(.secondary)
      }
      Section("Capabilities · public evidence, instance validation separate") {
        ForEach(Capability.allCases, id: \.self) { c in
          LabeledContent(c.rawValue, value: device.capabilities[c].rawValue)
        }
      }
    }.navigationTitle(device.name).onAppear { name = device.name }
  }
}
struct CollectionHealthView: View {
  @Environment(AppModel.self) var model
  var body: some View {
    List {
      Section("Collection") {
        Text(model.bluetooth.status)
        LabeledContent("Connected devices", value: String(model.bluetooth.connected.count))
        if let date = model.lastSample?.timestamp {
          LabeledContent("Last sample", value: date.formatted())
        }
        LabeledContent("Rejected packets", value: String(model.bluetooth.rejectedPackets))
        LabeledContent("History retrieval", value: "Not hardware validated")
      }
      Section("Limits and recovery") {
        Text(
          "Live heart-rate notification collection uses Core Bluetooth background mode and state restoration. Force-quit, permission revocation, phone restart, broadcast settings or competing apps can interrupt collection."
        )
        Text(
          "History adapters are version-gated. Full catch-up and concurrent-band wear detection remain unavailable until physical validation. Do not rely on this build for complete overnight coverage."
        )
        Text(
          "A connected band with plausible HR and unknown contact remains a source with uncertain wear. RSSI never establishes on-body status."
        )
      }
    }.navigationTitle("Collection health")
  }
}
struct ConflictView: View {
  @Environment(AppModel.self) var model
  var entityID: UUID
  @State private var heads: [Revision] = []
  var body: some View {
    List {
      Section {
        Text(
          "Both edits are preserved. Choosing a version creates a new revision referencing both parents."
        )
      }
      ForEach(heads) { r in
        VStack(alignment: .leading) {
          Text(r.createdAt, format: .dateTime)
          Text(r.deleted ? "Deleted" : (String(data: r.payload, encoding: .utf8) ?? "Encoded item"))
            .font(.caption).textSelection(.enabled)
          Button("Keep this version") {
            model.mutate {
              try await model.resolve(entityID: entityID, chosen: r)
              heads = []
            }
          }
        }
      }
    }.navigationTitle("Resolve edits").task {
      heads = (try? await model.store?.revisionHeads(entityID: entityID)) ?? []
    }
  }
}
struct HealthSettingsView: View {
  @Environment(AppModel.self) var model
  @State private var options = HealthService.Options()
  var body: some View {
    Form {
      Section("Import · select types") {
        Toggle("Heart rate", isOn: $options.heartRate)
        Toggle("Resting heart rate", isOn: $options.restingHeartRate)
        Toggle("HRV · SDNN", isOn: $options.hrv)
        Toggle("Sleep", isOn: $options.sleep)
        Toggle("Workouts", isOn: $options.workouts)
        Toggle("Weight", isOn: $options.weight)
      }
      Section("Export") {
        Toggle("Measured heart rate", isOn: $options.exportHeartRate)
        Toggle("Manually entered sleep", isOn: $options.exportSleep)
        Toggle("Recorded workouts", isOn: $options.exportWorkouts)
        Text(
          "RMSSD is never written into Health's SDNN type. Sleep exports use asleep-unspecified; padel exports use Other with Tempo activity metadata."
        ).font(.caption).foregroundStyle(.secondary)
      }
      Button("Request selected permissions") {
        Task {
          do { try await model.health?.authorize(options) } catch {
            model.errorMessage = error.localizedDescription
          }
        }
      }
      Button("Import available data") {
        Task {
          do {
            try await model.health?.importData(options)
            try await model.load()
          } catch { model.errorMessage = error.localizedDescription }
        }
      }
      if options.exportHeartRate {
        Button("Export recent measured HR") {
          Task {
            do { try await model.health?.exportHeartRate(model.canonical) } catch {
              model.errorMessage = error.localizedDescription
            }
          }
        }
      }
      if options.exportSleep || options.exportWorkouts {
        Button("Export supported sessions") {
          Task {
            do {
              try await model.health?.exportSessions(
                workouts: model.workouts, sleeps: model.sleeps, options: options)
            } catch { model.errorMessage = error.localizedDescription }
          }
        }
      }
      Text(model.health?.status ?? "Disabled in demonstration mode").font(.caption)
      Text(
        "Tempo excludes its own exports from imports. Other overlapping source observations are retained; the canonical timeline selects one. Health read denial may appear as empty results."
      ).font(.caption).foregroundStyle(.secondary)
    }.navigationTitle("Apple Health")
  }
}
