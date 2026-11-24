import Foundation
import UIKit

/// 量測點在照片上的位置（0–1，左上角是原點，照片本身沒有左右相反）。報告最上面的標註照這個畫
struct PhotoMarks: Codable, Equatable {
    /// 跟哪一次報告是同一次掃的
    var when: Date?
    var points: [String: UV] = [:]
    var brows: [[UV]] = []
    var eyes: [[UV]] = []
    var lips: [UV] = []
    /// 使用者拉的髮際線高度。跳過就是 nil
    var hairY: Double?

    subscript(_ lm: LM) -> UV? {
        get { points[lm.rawValue] }
        set { points[lm.rawValue] = newValue }
    }

    /// 全部要畫的點，算照片要裁多大用
    var all: [UV] {
        Array(points.values) + brows.flatMap { $0 } + eyes.flatMap { $0 } + lips
    }

    /// 照片要怎麼轉臉才是正的：看眉心到下巴（沒有就眼睛到嘴唇）往哪邊，挑最接近的 90 度。
    /// 已經是正的、或沒有點可以判斷，就是 identity。
    /// - Parameter size: 照片的大小。照片不是正方形，比方向之前要換成像素
    func turn(size: CGSize) -> Dihedral {
        guard let (top, bottom) = axis else { return .identity }
        let w = Double(size.width), h = Double(size.height)
        let down = UV(x: (bottom.x - top.x) * w, y: (bottom.y - top.y) * h)
        // 轉完以後，臉往下的方向有多少是真的朝下
        let match: (Dihedral) -> Double = { d in
            let end = d.apply(UV(x: 1, y: 0)), end2 = d.apply(UV(x: 0, y: 1)), zero = d.apply(UV(x: 0, y: 0))
            return (end.y - zero.y) * down.x + (end2.y - zero.y) * down.y
        }
        var best = Dihedral.identity
        for d in [Dihedral.quarterA, .quarterB, .rotate180] where match(d) > match(best) { best = d }
        return best
    }

    /// 照片轉了，標註跟著轉。髮際線是在躺著的照片上拉的高度，轉完沒有意義，拿掉
    func turned(_ d: Dihedral) -> PhotoMarks {
        guard d != .identity else { return self }
        var out = self
        out.points = points.mapValues(d.apply)
        out.brows = brows.map { $0.map(d.apply) }
        out.eyes = eyes.map { $0.map(d.apply) }
        out.lips = lips.map(d.apply)
        out.hairY = nil
        return out
    }

    /// 臉的上面和下面各一個點
    private var axis: (top: UV, bottom: UV)? {
        if let glabella = self[.glabella], let chin = self[.chin], glabella != chin { return (glabella, chin) }
        guard let top = Self.centre(eyes.flatMap { $0 }), let bottom = Self.centre(lips), top != bottom
        else { return nil }
        return (top, bottom)
    }

    private static func centre(_ list: [UV]) -> UV? {
        guard !list.isEmpty else { return nil }
        let n = Double(list.count)
        return UV(x: list.map(\.x).reduce(0, +) / n, y: list.map(\.y).reduce(0, +) / n)
    }
}

/// 報告最上面那張照片
struct FacePhoto {
    var image: UIImage
    var marks: PhotoMarks

    /// 照片躺著就連標註一起轉正，已經正的原樣還回來
    func upright() -> FacePhoto {
        let turn = marks.turn(size: image.size)
        guard turn != .identity else { return self }
        return FacePhoto(image: Self.redraw(image, turn), marks: marks.turned(turn))
    }

    /// 真的重畫一張。只改 imageOrientation 的話，直接拿像素的地方看到的還是躺著的
    private static func redraw(_ image: UIImage, _ turn: Dihedral) -> UIImage {
        let old = image.size
        let angle: CGFloat
        switch turn {
        case .quarterA: angle = .pi / 2 // 順時針
        case .quarterB: angle = -.pi / 2
        case .rotate180: angle = .pi
        default: return image
        }
        let size = turn == .rotate180 ? old : CGSize(width: old.height, height: old.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            context.cgContext.rotate(by: angle)
            image.draw(in: CGRect(x: -old.width / 2, y: -old.height / 2, width: old.width, height: old.height))
        }
    }
}

extension Storage {
    /// 照片只留最近一次的那一張。檔案鎖機就讀不到，也不跟著 iCloud 備份走，所以不會離開這支手機（鐵則 1）
    func savePhoto(_ photo: FacePhoto) {
        removePhoto()
        guard let jpeg = photo.image.jpegData(compressionQuality: 0.88) else { return }
        saveLocalOnly(jpeg, to: .photo)
        save(photo.marks, to: .photoMarks)
        excludeFromBackup(.photoMarks)
    }

    func loadPhoto(when: Date) -> FacePhoto? {
        guard let marks = load(PhotoMarks.self, from: .photoMarks), marks.when == when, let data = data(.photo),
            let image = UIImage(data: data)
        else { return nil }
        // 2026-11-24 以前的版本會存到躺著的照片，讀進來時轉正（存著的檔案不改）
        return FacePhoto(image: image, marks: marks).upright()
    }

    func removePhoto() {
        remove(.photo)
        remove(.photoMarks)
    }
}
