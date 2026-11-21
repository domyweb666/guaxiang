#if DEVTOOLS
    import SwiftUI

    /// 開發工具。只在編譯時有開 DEVTOOLS 的版本裡出現，上架前整區拿掉。
    struct DevToolsView: View {
        @EnvironmentObject private var model: AppModel
        @Environment(\.dismiss) private var dismiss
        @State private var key = ""
        @State private var hasKey = Keychain.get(Storage.Keys.devAPIKey) != nil
        @State private var map = VertexMap.current()

        var body: some View {
            Page {
                SectionTitle("頂點對照")
                Card {
                    CardBlock(divider: false) {
                        Text("已對 \(VertexMap.meshLandmarks.count - map.missing.count) / \(VertexMap.meshLandmarks.count) 個點")
                            .font(.headline)
                        Note("ARKit 的臉部網格有一千兩百多個頂點。要先找出眉心、眼角、鼻尖這些點各是第幾號，掃描才量得出數字。對完把 JSON 分享出來，貼回 repo 的 arkit-vertex-map.json。")
                        NavigationLink("打開對照工具") { VertexMapperView() }
                            .buttonStyle(.primary)
                    }
                }

                SectionTitle("範例報告")
                Card {
                    CardBlock(divider: false) {
                        Note("用一組假數字開報告，看畫面長什麼樣。不會蓋掉你存的報告。")
                        Button("開範例報告") {
                            model.show(Self.sample(rulesVersion: model.rules?.version ?? ""), save: false)
                            dismiss()
                        }
                        .buttonStyle(.ghost)
                    }
                }

                SectionTitle("問古書的金鑰")
                Card {
                    CardBlock(divider: false) {
                        Note("中繼站還沒架好之前，貼自己的 Anthropic 金鑰可以先試問答。金鑰只存在這支手機的鑰匙圈，直接從手機送出。")
                        if hasKey {
                            Text("已經存了一把金鑰")
                            Button("刪掉金鑰") {
                                Keychain.delete(Storage.Keys.devAPIKey)
                                hasKey = false
                            }
                            .buttonStyle(.ghost)
                        } else {
                            SecureField("sk-ant-...", text: $key)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(10)
                                .background(Theme.fill)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.fieldRadius))
                            Button("存金鑰") {
                                let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else { return }
                                Keychain.set(trimmed, for: Storage.Keys.devAPIKey)
                                key = ""
                                hasKey = true
                            }
                            .buttonStyle(.ghost)
                        }
                    }
                }
            }
            .navigationTitle("開發工具")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { map = VertexMap.current() }
        }

        /// 假數字，只用來看報告畫面
        static func sample(rulesVersion: String) -> Measurement {
            let values: [String: Double] = [
                "santing_U": 1.06, "santing_M": 0.95, "santing_L": 0.99, "santing_dev": 0.06,
                "face_aspect": 1.35, "fore_jaw": 0.94, "jaw_angle": 135.7, "brow_eye": 0.18, "brow_tail": 3.2,
                "yintang": 0.87, "eye_lw": 3.04, "nose_dev": 0.004, "mouth_ipd": 0.875, "mouth_corner": -0.014,
                "lip_thick": 0.30, "renzhong": 0.27, "nose_prom": 0.10, "cheek_prom": 0.146
            ]
            return Measurement(
                when: Date(timeIntervalSince1970: 1_795_000_000), frames: 30, light: 140, hasHair: true,
                answers: Answers(),
                F: values.mapValues { FeatureStat(v: $0, iqr: abs($0) * 0.01, unstable: false) },
                rulesVersion: rulesVersion, gaps: ["這是範例報告，數字是假的，不是你的臉。"])
        }
    }

    /// 頂點對照工具：定格一張臉，把網格的每個頂點畫在照片上。點一個頂點，指定它是哪個點位。
    struct VertexMapperView: View {
        @StateObject private var session = FaceScanSession()
        @State private var map = VertexMap.current()
        @State private var selected: Int?
        @State private var target: LM = VertexMap.meshLandmarks[0]
        @State private var zoom: CGFloat = 1
        @State private var baseZoom: CGFloat = 1
        @State private var pan: CGSize = .zero
        @State private var basePan: CGSize = .zero

        var body: some View {
            VStack(spacing: 10) {
                if let shot = session.snapshot {
                    editor(shot)
                } else {
                    live
                }
            }
            .padding(.horizontal, Theme.margin)
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("頂點對照")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { session.start(collect: false) }
            .onDisappear { session.stop() }
            .onChange(of: session.snapshot != nil) { _, frozen in
                if frozen { session.stop() }
            }
        }

        private var currentText: String {
            if let index = map[target] { return "頂點 \(index)" }
            return "還沒對"
        }

        private var live: some View {
            VStack(spacing: 10) {
                CameraPreview(session: session)
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                Note(session.failure ?? "正對鏡頭、表情放鬆，按定格。眼鏡要拿下來。")
                Button("定格") { session.requestSnapshot() }
                    .buttonStyle(.primary)
                Spacer(minLength: 0)
            }
        }

        private func editor(_ shot: MeshSnapshot) -> some View {
            let aspect = shot.image.size.width / max(1, shot.image.size.height)
            return VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geo in
                    let place: (UV) -> CGPoint = { uv in
                        CGPoint(
                            x: (CGFloat(uv.x) - 0.5) * geo.size.width * zoom + geo.size.width / 2 + pan.width,
                            y: (CGFloat(uv.y) - 0.5) * geo.size.height * zoom + geo.size.height / 2 + pan.height)
                    }
                    Canvas { context, _ in
                        let origin = place(UV(x: 0, y: 0)), corner = place(UV(x: 1, y: 1))
                        context.draw(
                            Image(uiImage: shot.image),
                            in: CGRect(x: origin.x, y: origin.y, width: corner.x - origin.x, height: corner.y - origin.y))
                        let assigned = Dictionary(
                            map.indices.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
                        for (i, uv) in shot.points.enumerated() {
                            let p = place(uv)
                            guard p.x > -10, p.y > -10, p.x < geo.size.width + 10, p.y < geo.size.height + 10
                            else { continue }
                            let isSelected = i == selected
                            let isAssigned = assigned[i] != nil
                            let r: CGFloat = isSelected ? 5 : isAssigned ? 4 : 1.5
                            let color: Color = isSelected ? .yellow : isAssigned ? .green : .white.opacity(0.75)
                            context.fill(
                                Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                                with: .color(color))
                            if isSelected || zoom >= 5 {
                                context.draw(
                                    Text("\(i)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.yellow),
                                    at: CGPoint(x: p.x, y: p.y - 9))
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture().onEnded { tap in
                            var bestIndex: Int?
                            var bestDistance = CGFloat.greatestFiniteMagnitude
                            for (i, uv) in shot.points.enumerated() {
                                let p = place(uv)
                                let d = hypot(p.x - tap.location.x, p.y - tap.location.y)
                                if d < bestDistance {
                                    bestDistance = d
                                    bestIndex = i
                                }
                            }
                            if bestDistance < 30 { selected = bestIndex }
                        }
                    )
                    .simultaneousGesture(
                        MagnifyGesture()
                            .onChanged { zoom = min(12, max(1, baseZoom * $0.magnification)) }
                            .onEnded { _ in baseZoom = zoom }
                    )
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged {
                                pan = CGSize(
                                    width: basePan.width + $0.translation.width,
                                    height: basePan.height + $0.translation.height)
                            }
                            .onEnded { _ in basePan = pan }
                    )
                }
                .aspectRatio(aspect, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Note("兩指放大、單指拖動、點一下選頂點。照片沒有左右相反（跟自拍預覽不一樣）。綠點是已經指定的。")
                Note(shot.info)

                Menu {
                    ForEach(VertexMap.meshLandmarks, id: \.self) { lm in
                        Button {
                            target = lm
                            selected = map[lm]
                        } label: {
                            Text((map[lm] != nil ? "✓ " : "　 ") + lm.plainName)
                        }
                    }
                } label: {
                    HStack {
                        Text("要對的點：\(target.plainName)").multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .padding(12)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.fieldRadius))
                }
                Note("網頁版點位 \(target.mediapipeIndex)・目前：" + currentText)

                if let selected, shot.faceX.indices.contains(selected) {
                    let side = shot.faceX[selected] < -0.004 ? -1 : shot.faceX[selected] > 0.004 ? 1 : 0
                    if target.side != 0, side != 0, side != target.side {
                        Note("這個頂點在你的\(side < 0 ? "右" : "左")臉，但要對的點在另一邊。", warn: true)
                    }
                    Button("把頂點 \(selected) 指定給這個點") {
                        map[target] = selected
                        map.saveAsOverride()
                        if let next = map.missing.first { target = next }
                    }
                    .buttonStyle(.primary)
                }

                HStack(spacing: 10) {
                    Button("重拍") {
                        selected = nil
                        session.start(collect: false)
                    }
                    .buttonStyle(.ghost)
                    ShareLink(item: map.exportJSON) {
                        Text("分享 JSON（\(VertexMap.meshLandmarks.count - map.missing.count)/\(VertexMap.meshLandmarks.count)）")
                    }
                    .buttonStyle(.ghost)
                }
                Spacer(minLength: 0)
            }
        }
    }
#endif
