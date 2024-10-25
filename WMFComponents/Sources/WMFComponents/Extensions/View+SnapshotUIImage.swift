import UIKit
import SwiftUI

 extension View {
     /// Captures a snapshot of the SwiftUI view as a UIImage.
     /// - Returns: A snapshot of the SwiftUI view as a UIImage.
     func snapshot() -> UIImage {
         // Create a UIHostingController hosting the SwiftUI view.
         let controller = UIHostingController(rootView: self)

         // Make sure the view is laid out correctly.
         let view = controller.view
         let targetSize = controller.view.intrinsicContentSize
         view?.bounds = CGRect(origin: .zero, size: targetSize)
         view?.backgroundColor = .clear

         // Render the view into an image.
         let renderer = UIGraphicsImageRenderer(size: targetSize)
         return renderer.image { _ in
             view?.drawHierarchy(in: view!.bounds, afterScreenUpdates: true)
         }
     }
 }
