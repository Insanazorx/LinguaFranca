import SwiftUI

extension View {
    @ViewBuilder func nativeFormStyle() -> some View {
        formStyle(.grouped)
    }
    @ViewBuilder func inlineNavigationTitle() -> some View {
        self
    }
    @ViewBuilder func nativeSheetSize(width:CGFloat=600,height:CGFloat=600) -> some View {
        frame(minWidth:width,idealWidth:width,minHeight:height,idealHeight:height)
    }
    @ViewBuilder func vocabularySheetPresentation() -> some View {
        nativeSheetSize(width:600,height:640)
    }
}
