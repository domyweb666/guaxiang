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
}

/// 報告最上面那張照片
struct FacePhoto {
    var image: UIImage
    var marks: PhotoMarks
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
        return FacePhoto(image: image, marks: marks)
    }

    func removePhoto() {
        remove(.photo)
        remove(.photoMarks)
    }
}
