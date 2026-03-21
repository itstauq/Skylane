import SwiftUI

struct NotchContentView: View {
    var vm: NotchViewModel

    var body: some View {
        NotchShape(
            topCornerRadius: 0,
            bottomCornerRadius: vm.isElevated ? 12 : 8
        )
        .fill(.black)
        .frame(width: vm.notchWidth - 2, height: vm.notchHeight)
        .shadow(
            color: .white.opacity(vm.isElevated ? 0.5 : 0),
            radius: vm.isElevated ? 8 : 0
        )
        .scaleEffect(vm.isElevated ? 1.075 : 1.0, anchor: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct NotchBlurView: View {
    var vm: NotchViewModel

    var body: some View {
        EmptyView()
    }
}
