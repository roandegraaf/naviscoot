import SwiftUI
import UIKit

// Dutch sign D103, the signpost for a moped path that leaves the carriageway. The artwork points right; a path that
// leaves on the left shows it mirrored.
struct MopedPathSign: View {
    let side: MopedPathEntry

    static let red = Color(hex: 0xAA0000)

    var body: some View {
        Image("MopedPathSign")
            .resizable()
            .scaledToFit()
            .scaleEffect(x: side == .left ? -1 : 1, y: 1)
    }

    static let leftMapIcon = mapIcon(.left)
    static let rightMapIcon = mapIcon(.right)

    private static func mapIcon(_ side: MopedPathEntry) -> UIImage {
        let sign = CGSize(width: 22, height: 33)
        let shadowRadius: CGFloat = 2
        let canvas = CGSize(width: sign.width + shadowRadius * 2, height: sign.height + shadowRadius * 2)
        return UIGraphicsImageRenderer(size: canvas).image { context in
            let cg = context.cgContext
            cg.setShadow(offset: .zero, blur: shadowRadius * 2, color: UIColor.black.withAlphaComponent(0.35).cgColor)
            if side == .left {
                cg.translateBy(x: canvas.width, y: 0)
                cg.scaleBy(x: -1, y: 1)
            }
            UIImage(named: "MopedPathSign")?.draw(in: CGRect(origin: CGPoint(x: shadowRadius, y: shadowRadius), size: sign))
        }
    }
}
