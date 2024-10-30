import SwiftUI

public struct WMFYearInReviewView: View {
    @ObservedObject var appEnvironment = WMFAppEnvironment.current
    @ObservedObject var viewModel: WMFYearInReviewViewModel

    var theme: WMFTheme {
        return appEnvironment.theme
    }

    public var donePressed: (() -> Void)?

    public init(viewModel: WMFYearInReviewViewModel) {
        self.viewModel = viewModel
        UINavigationBar.appearance().backgroundColor = theme.midBackground
    }

    let configuration = WMFSmallButton.Configuration(style: .quiet, trailingIcon: nil)

    public var body: some View {
        NavigationView {
            VStack {
                HStack {
                    if !viewModel.isFirstSlide {
                        WMFYearInReviewDonateButton(viewModel: viewModel)
                    }
                    Spacer()
                    Button(action: {
                        viewModel.logYearInReviewDidTapDone()
                        donePressed?()
                    }) {
                        Text(viewModel.localizedStrings.doneButtonTitle)
                            .foregroundStyle(Color(uiColor: theme.link))
                            .font(Font(WMFFont.for(.semiboldHeadline)))
                    }
                }
                .padding()
                if viewModel.isFirstSlide {
                    WMFYearInReviewScrollView(
                        scrollViewContents: scrollViewContent,
                        contents: { AnyView(buttons) },
                        imageName: "read_gradient",
                        imageOverlay: "globe")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear {
                            viewModel.logYearInReviewSlideDidAppear()
                        }
                } else {
                    VStack {
                        TabView(selection: $viewModel.currentSlide) {
                            WMFSlideShow(currentSlide: $viewModel.currentSlide, slides: viewModel.slides)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 48)
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        viewModel.logYearInReviewSlideDidAppear()
                    }
                }
            }
            .background(Color(uiColor: theme.midBackground))
            .onChange(of: viewModel.currentSlide) { newSlide in
                // Logs slide impressions and next taps
                viewModel.logYearInReviewSlideDidAppear()
            }
            .toolbar {
                if !viewModel.isFirstSlide {
                    ToolbarItem(placement: .bottomBar) {
                        HStack(alignment: .center) {
                            Button(action: {
                                viewModel.handleShare(for: viewModel.currentSlide)
                            }) {
                                HStack(alignment: .center, spacing: 6) {
                                    if let uiImage = WMFSFSymbolIcon.for(symbol: .share, font: .semiboldHeadline) {
                                        Image(uiImage: uiImage)
                                            .foregroundStyle(Color(uiColor: theme.link))
                                    }
                                    Text(viewModel.localizedStrings.shareButtonTitle)
                                        .foregroundStyle(Color(uiColor: theme.link))
                                }
                                .font(Font(WMFFont.for(.semiboldHeadline)))
                            }
                            .frame(maxWidth: .infinity)
                            Spacer()
                            HStack(spacing: 9) {
                                ForEach(0..<viewModel.slides.count, id: \.self) { index in
                                    Circle()
                                        .fill(index == viewModel.currentSlide ? Color(uiColor: theme.link) : Color(uiColor: theme.link.withAlphaComponent(0.3)))
                                        .frame(width: 7, height: 7)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            Spacer()
                            Button(action: {
                                withAnimation {
                                    viewModel.logYearInReviewSlideDidTapNext()
                                    viewModel.nextSlide()
                                }
                            }) {
                                Text(viewModel.localizedStrings.nextButtonTitle)
                                    .foregroundStyle(Color(uiColor: theme.link))
                                    .font(Font(WMFFont.for(.semiboldHeadline)))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            Spacer()
        }
        .background(Color(uiColor: theme.midBackground))
        .navigationViewStyle(.stack)
        .environment(\.colorScheme, theme.preferredColorScheme)
        .frame(maxHeight: .infinity)
    }

    private var scrollViewContent: some View {
        VStack(spacing: 48) {
            VStack(alignment: .leading, spacing: 16) {
                Text(viewModel.localizedStrings.firstSlideTitle)
                    .font(Font(WMFFont.for(.boldTitle1)))
                Text(viewModel.localizedStrings.firstSlideSubtitle)
                    .font(Font(WMFFont.for(.title3)))
            }
            .foregroundStyle(Color(uiColor: theme.text))
        }
    }

    private var buttons: some View {
        VStack {
            WMFLargeButton(configuration: .primary, title: viewModel.localizedStrings.firstSlideCTA) {
                withAnimation(.easeInOut(duration: 0.75)) {
                    viewModel.loggingDelegate?.logYearInReviewIntroDidTapContinue()
                    viewModel.getStarted()
                }
            }
            WMFSmallButton(configuration: configuration, title: viewModel.localizedStrings.firstSlideHide) {
                viewModel.loggingDelegate?.logYearInReviewIntroDidTapDisable()
                // TODO: Implement hide this feature
            }
        }
    }
}
