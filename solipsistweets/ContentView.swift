//
//  ContentView.swift
//  solipsistweets
//

import Combine
import CoreMotion
import SwiftUI
import UIKit
import WebKit

struct ContentView: View {
    private let screenTimeBadgeThreshold: TimeInterval = 20 * 60
    private static let testFlightURL = URL.required(string: "https://testflight.apple.com/join/N3DtJcgD")
    @Binding var requestedURL: URL
    @StateObject private var shakeDetector = ShakeDetector()
    @State private var showShareBanner = false
    @State private var isShareSheetPresented = false
    @State private var hideShareBannerTask: Task<Void, Never>?
    @State private var showRemoveCurrentTabConfirmation = false
    @State private var isSwitcherPressed = false
    @State private var switchProgress: CGFloat = 0
    @State private var switchCompletionTask: Task<Void, Never>?
    @State private var pendingRoutedTab: SocialTab?
    @State private var requestedURLsByTab: [SocialTab: URL] = [:]
    @EnvironmentObject private var screenTimeTracker: OnScreenTimeTracker
    @Environment(\.colorScheme) private var colorScheme
    let activeTab: SocialTab
    var nextTab: SocialTab?
    var removableTabs: [SocialTab] = []
    var setupTabs: [SocialTab] = []
    var onSwitchTab: (() -> Void)?
    var onRemoveTab: ((SocialTab) -> Void)?
    var onSetupTab: ((SocialTab) -> Void)?
    var onOpenURLInTab: ((URL, SocialTab) -> Void)?

    init(
        requestedURL: Binding<URL>,
        activeTab: SocialTab,
        nextTab: SocialTab? = nil,
        removableTabs: [SocialTab] = [],
        setupTabs: [SocialTab] = [],
        onSwitchTab: (() -> Void)? = nil,
        onRemoveTab: ((SocialTab) -> Void)? = nil,
        onSetupTab: ((SocialTab) -> Void)? = nil,
        onOpenURLInTab: ((URL, SocialTab) -> Void)? = nil
    ) {
        _requestedURL = requestedURL
        self.activeTab = activeTab
        self.nextTab = nextTab
        self.removableTabs = removableTabs
        self.setupTabs = setupTabs
        self.onSwitchTab = onSwitchTab
        self.onRemoveTab = onRemoveTab
        self.onSetupTab = onSetupTab
        self.onOpenURLInTab = onOpenURLInTab
    }

    var body: some View {
        ZStack {
            flipDeck

            if let nextTab, pendingRoutedTab == nil {
                SideSwitcherControl(
                    tab: nextTab,
                    activeTab: activeTab,
                    progress: switchProgress,
                    isPressed: isSwitcherPressed,
                    isRemoveDialogPresented: $showRemoveCurrentTabConfirmation,
                    removeTabChoices: removeTabChoices,
                    onTap: beginSwitcherTap,
                    onDragChanged: updateSwitchDrag,
                    onDragEnded: finishSwitchDrag,
                    onPressing: updateSwitcherPressState,
                    onLongPress: presentRemoveTabChoices,
                    onRemoveTab: { tab in
                        onRemoveTab?(tab)
                    }
                )
            }
        }
        .onAppear {
            prepareVisibleTabURLs()
            shakeDetector.start()
        }
        .onDisappear {
            shakeDetector.stop()
            switchCompletionTask?.cancel()
            hideShareBannerTask?.cancel()
        }
        .onChange(of: shakeDetector.shakeCount) { _, _ in
            presentShareBanner()
        }
        .onChange(of: requestedURL) { _, _ in
            requestedURLsByTab[activeTab] = requestedURL
        }
        .onChange(of: activeTab) { _, _ in
            prepareVisibleTabURLs()
        }
        .sheet(isPresented: $isShareSheetPresented) {
            ShareSheet(activityItems: [Self.testFlightURL])
        }
    }

    private var flipDeck: some View {
        ZStack {
            ForEach(visibleTabs) { tab in
                TabWebSurface(url: urlBinding(for: tab), tab: tab, onOpenURLInTab: openURLInTab)
                    .opacity(opacity(for: tab))
                    .rotation3DEffect(
                        .degrees(rotationDegrees(for: tab)),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.68
                    )
                    .zIndex(zIndex(for: tab))
                    .allowsHitTesting(tab == activeTab && switchProgress < 0.02)
            }
        }
        .scaleEffect(1 - (0.035 * sin(Double(switchProgress) * .pi)))
        .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.86), value: switchProgress)
        .allowsHitTesting(switchProgress < 0.02)
        .ignoresSafeArea(edges: [.bottom])
        .overlay {
            if shouldShowScreenTimeBadge {
                Text(formatDuration(screenTimeTracker.secondsToday))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(badgeForegroundColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(badgeBackgroundColor))
                    .overlay(
                        Capsule().stroke(badgeForegroundColor.opacity(0.08), lineWidth: 0.5)
                    )
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea(edges: [.bottom])
                    .onTapGesture {
                        UIControl().sendAction(#selector(NSXPCConnection.suspend),
                                               to: UIApplication.shared,
                                               for: nil)
                    }
            }
        }
        .overlay(alignment: .top) {
            if showShareBanner {
                VStack(spacing: 8) {
                    Button {
                        isShareSheetPresented = true
                        dismissShareBanner()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                            Text("Share TestFlight")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .foregroundStyle(.primary)
                        .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    ForEach(setupTabs) { tab in
                        Button {
                            onSetupTab?(tab)
                            dismissShareBanner()
                        } label: {
                            HStack(spacing: 8) {
                                Text(tab.emoji)
                                Text(tab.setupTitle)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .foregroundStyle(.primary)
                            .background(.regularMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    if canRemoveAccounts {
                        Button {
                            dismissShareBanner()
                            presentRemoveTabChoices()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "person.crop.circle.badge.minus")
                                    .font(.subheadline.weight(.semibold))
                                Text("Remove Account")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .foregroundStyle(.primary)
                            .background(.regularMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var visibleTabs: [SocialTab] {
        SocialTab.allCases.filter { tab in
            tab == activeTab || tab == flipTargetTab
        }
    }

    private var flipTargetTab: SocialTab? {
        pendingRoutedTab ?? nextTab
    }

    private var removeTabChoices: [SocialTab] {
        [.bluesky, .x].filter { removableTabs.contains($0) }
    }

    private var canRemoveAccounts: Bool {
        removeTabChoices.count > 1
    }

    private var shouldShowScreenTimeBadge: Bool {
        screenTimeTracker.secondsToday >= screenTimeBadgeThreshold
    }

    private var badgeForegroundColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var badgeBackgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }

    private var frontRotationDegrees: Double {
        connectedEdgeRotationDegrees(progress: switchProgress, direction: switchDirection)
    }

    private var backRotationDegrees: Double {
        frontRotationDegrees - (switchDirection * 180)
    }

    private var switchDirection: Double {
        activeTab == .x ? -1 : 1
    }

    private func prepareVisibleTabURLs() {
        if requestedURLsByTab[activeTab] == nil {
            requestedURLsByTab[activeTab] = requestedURL
        }
        if let nextTab, requestedURLsByTab[nextTab] == nil {
            requestedURLsByTab[nextTab] = nextTab.startURL
        }
        if let pendingRoutedTab, requestedURLsByTab[pendingRoutedTab] == nil {
            requestedURLsByTab[pendingRoutedTab] = pendingRoutedTab.startURL
        }
    }

    private func urlBinding(for tab: SocialTab) -> Binding<URL> {
        Binding(
            get: {
                requestedURLsByTab[tab] ?? (tab == activeTab ? requestedURL : tab.startURL)
            },
            set: { newURL in
                requestedURLsByTab[tab] = newURL
                if tab == activeTab {
                    requestedURL = newURL
                }
            }
        )
    }

    private func openURLInTab(_ url: URL, tab: SocialTab) {
        requestedURLsByTab[tab] = url
        guard tab != activeTab else {
            requestedURL = url
            return
        }

        completeSwitch(to: tab) {
            onOpenURLInTab?(url, tab)
        }
    }

    private func opacity(for tab: SocialTab) -> Double {
        if tab == activeTab {
            return switchProgress <= 0.5 ? 1 : 0
        }
        if tab == flipTargetTab {
            return switchProgress > 0.5 ? 1 : 0
        }
        return 0
    }

    private func rotationDegrees(for tab: SocialTab) -> Double {
        if tab == activeTab {
            return frontRotationDegrees
        }
        if tab == flipTargetTab {
            return backRotationDegrees
        }
        return 0
    }

    private func zIndex(for tab: SocialTab) -> Double {
        if tab == activeTab {
            return switchProgress <= 0.5 ? 1 : 0
        }
        if tab == flipTargetTab {
            return switchProgress > 0.5 ? 1 : 0
        }
        return -1
    }

    private func presentShareBanner() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            showShareBanner = true
        }
        scheduleShareBannerDismissal()
    }

    private func dismissShareBanner() {
        hideShareBannerTask?.cancel()
        hideShareBannerTask = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            showShareBanner = false
        }
    }

    private func scheduleShareBannerDismissal(after seconds: TimeInterval = 3.5) {
        hideShareBannerTask?.cancel()
        hideShareBannerTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showShareBanner = false
                }
                hideShareBannerTask = nil
            }
        }
    }

    private func updateSwitcherPressState(_ isPressing: Bool) {
        withAnimation(.spring(response: 0.18, dampingFraction: 0.72)) {
            isSwitcherPressed = isPressing
        }
    }

    private func beginSwitcherTap() {
        guard nextTab != nil else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        completeSwitch {
            onSwitchTab?()
        }
    }

    private func updateSwitchDrag(_ translationWidth: CGFloat, screenWidth: CGFloat) {
        guard nextTab != nil else { return }
        switchCompletionTask?.cancel()
        let progress = switchProgress(for: translationWidth, screenWidth: screenWidth)
        withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.82)) {
            isSwitcherPressed = true
            switchProgress = progress
        }
    }

    private func finishSwitchDrag(_ translationWidth: CGFloat, predictedTranslationWidth: CGFloat, screenWidth: CGFloat) {
        guard nextTab != nil else { return }
        let progress = switchProgress(for: translationWidth, screenWidth: screenWidth)
        let predictedProgress = switchProgress(for: predictedTranslationWidth, screenWidth: screenWidth)
        if max(progress, predictedProgress) >= 0.48 {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            completeSwitch {
                onSwitchTab?()
            }
        } else {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                switchProgress = 0
                isSwitcherPressed = false
            }
        }
    }

    private func switchProgress(for translationWidth: CGFloat, screenWidth: CGFloat) -> CGFloat {
        let signedTranslation = activeTab == .x ? -translationWidth : translationWidth
        let travelDistance = max(screenWidth, 1)
        return min(max(signedTranslation / travelDistance, 0), 1)
    }

    private func completeSwitch(to routedTab: SocialTab? = nil, completion: @escaping @MainActor () -> Void) {
        switchCompletionTask?.cancel()
        pendingRoutedTab = routedTab
        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
            switchProgress = 1
            isSwitcherPressed = false
        }
        switchCompletionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 340_000_000)
            guard !Task.isCancelled else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            transaction.animation = nil
            withTransaction(transaction) {
                completion()
                switchProgress = 0
                pendingRoutedTab = nil
            }
            switchCompletionTask = nil
        }
    }

    private func presentRemoveTabChoices() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.bouncy(duration: 0.42, extraBounce: 0.22)) {
            isSwitcherPressed = false
        }
        showRemoveCurrentTabConfirmation = true
    }
}

private struct TabWebSurface: View {
    @Binding var url: URL
    let tab: SocialTab
    let onOpenURLInTab: (URL, SocialTab) -> Void
    @State private var isLoading = true
    @State private var lastErrorDescription: String?

    var body: some View {
        ZStack {
            WebView(
                url: url,
                isLoading: $isLoading,
                lastErrorDescription: $lastErrorDescription,
                activeTab: tab,
                onOpenURLInTab: onOpenURLInTab
            )
            .ignoresSafeArea(edges: [.bottom])

            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
            }
        }
        .overlay(alignment: .bottom) {
            if let lastErrorDescription {
                Text(lastErrorDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                    .padding(.horizontal)
                    .allowsHitTesting(false)
            }
        }
    }
}

private func connectedEdgeRotationDegrees(progress: CGFloat, direction: Double) -> Double {
    let clampedProgress = min(max(Double(progress), 0), 1)
    let projectedEdgePosition = 1 - (2 * clampedProgress)
    let radians = acos(projectedEdgePosition)
    return direction * radians * 180 / .pi
}

private struct SideSwitcherControl: View {
    private let diameter: CGFloat = 86
    private let glyphSize: CGFloat = 24
    private let edgeIconOffset: CGFloat = 8
    private let verticalEdgePadding: CGFloat = 12
    private let longPressMinimumDuration: TimeInterval = 0.5
    private let longPressMaximumDistance: CGFloat = 10
    private let removePopoverWidth: CGFloat = 240
    private let removePopoverEstimatedHeight: CGFloat = 128
    private let removePopoverSpacing: CGFloat = 12
    private let removePopoverScreenPadding: CGFloat = 8

    let tab: SocialTab
    let activeTab: SocialTab
    let progress: CGFloat
    let isPressed: Bool
    @Binding var isRemoveDialogPresented: Bool
    let removeTabChoices: [SocialTab]
    let onTap: () -> Void
    let onDragChanged: (CGFloat, CGFloat) -> Void
    let onDragEnded: (CGFloat, CGFloat, CGFloat) -> Void
    let onPressing: (Bool) -> Void
    let onLongPress: () -> Void
    let onRemoveTab: (SocialTab) -> Void
    @AppStorage("sideSwitcherVerticalPlacement") private var verticalPlacement = 0.5
    @State private var isDraggingSwitcher = false
    @State private var dragStartVerticalPlacement = 0.5

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if isRemoveDialogPresented {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.16)) {
                                isRemoveDialogPresented = false
                            }
                        }
                }

                button
                    .overlay {
                        LongPressRecognizer(
                            minimumPressDuration: longPressMinimumDuration,
                            allowableMovement: longPressMaximumDistance,
                            onBegan: onLongPress
                        )
                    }
                    .position(x: xPosition(in: proxy.size.width), y: yPosition(in: proxy.size.height))
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 4, coordinateSpace: .global)
                            .onChanged { value in
                                handleDragChanged(value, in: proxy.size)
                            }
                            .onEnded { value in
                                handleDragEnded(value, in: proxy.size)
                            }
                    )
                    .onTapGesture(perform: onTap)
                    .accessibilityLabel("Switch to \(tab.displayName)")
                    .accessibilityHint("Drag across the screen to flip apps. Drag up or down to move the switcher. Long press to remove tabs.")
                    .accessibilityAddTraits(.isButton)

                if isRemoveDialogPresented {
                    removePopover(in: proxy.size)
                        .zIndex(1)
                }
            }
            .animation(
                .spring(response: 0.24, dampingFraction: 0.86),
                value: isRemoveDialogPresented
            )
        }
        .ignoresSafeArea()
    }

    private func removePopover(in size: CGSize) -> some View {
        SwitcherRemovePopover(
            choices: removeTabChoices,
            arrowEdge: popoverArrowEdge,
            onRemoveTab: { tab in
                withAnimation(.easeOut(duration: 0.16)) {
                    isRemoveDialogPresented = false
                }
                onRemoveTab(tab)
            }
        )
        .frame(width: removePopoverWidth)
        .position(
            x: removePopoverXPosition(in: size.width),
            y: removePopoverYPosition(in: size.height)
        )
    }

    private var popoverArrowEdge: Edge {
        activeTab == .x ? .trailing : .leading
    }

    private func removePopoverXPosition(in width: CGFloat) -> CGFloat {
        let buttonX = xPosition(in: width)
        let buttonHalfWidth = diameter * 0.5
        let popoverHalfWidth = removePopoverWidth * 0.5
        let idealX: CGFloat
        if activeTab == .x {
            idealX = buttonX - buttonHalfWidth - removePopoverSpacing - popoverHalfWidth
        } else {
            idealX = buttonX + buttonHalfWidth + removePopoverSpacing + popoverHalfWidth
        }
        return min(
            max(idealX, popoverHalfWidth + removePopoverScreenPadding),
            width - popoverHalfWidth - removePopoverScreenPadding
        )
    }

    private func removePopoverYPosition(in height: CGFloat) -> CGFloat {
        let popoverHalfHeight = removePopoverEstimatedHeight * 0.5
        return min(
            max(yPosition(in: height), popoverHalfHeight + removePopoverScreenPadding),
            height - popoverHalfHeight - removePopoverScreenPadding
        )
    }

    private var button: some View {
        ZStack {
            Text(tab.emoji)
                .font(.system(size: glyphSize))
                .frame(width: diameter, height: diameter)
                .offset(x: iconHorizontalOffset)
                .opacity(progress <= 0.5 ? 1 : 0)
                .rotation3DEffect(
                    .degrees(iconFrontRotationDegrees),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.68
                )

            Text(activeTab.emoji)
                .font(.system(size: glyphSize))
                .frame(width: diameter, height: diameter)
                .offset(x: iconHorizontalOffset)
                .opacity(progress > 0.5 ? 1 : 0)
                .rotation3DEffect(
                    .degrees(iconBackRotationDegrees),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.68
                )
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .interactiveLiquidGlass(in: Circle())
        .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 6)
    }

    private var iconFrontRotationDegrees: Double {
        connectedEdgeRotationDegrees(progress: progress, direction: switchDirection)
    }

    private var iconBackRotationDegrees: Double {
        iconFrontRotationDegrees - (switchDirection * 180)
    }

    private var switchDirection: Double {
        activeTab == .x ? -1 : 1
    }

    private var iconHorizontalOffset: CGFloat {
        let startOffset = activeTab == .x ? -edgeIconOffset : edgeIconOffset
        let endOffset = -startOffset
        return startOffset + ((endOffset - startOffset) * min(max(progress, 0), 1))
    }

    private var clampedProgress: CGFloat {
        min(max(progress, 0), 1)
    }

    private var verticalInset: CGFloat {
        (diameter * 0.5) + verticalEdgePadding
    }

    private var clampedVerticalPlacement: Double {
        min(max(verticalPlacement, 0), 1)
    }

    private func xPosition(in width: CGFloat) -> CGFloat {
        let leading: CGFloat = 0
        let trailing = width
        let start = activeTab == .x ? trailing : leading
        let end = activeTab == .x ? leading : trailing
        return start + ((end - start) * clampedProgress)
    }

    private func yPosition(in height: CGFloat) -> CGFloat {
        let range = verticalRange(in: height)
        return range.min + ((range.max - range.min) * CGFloat(clampedVerticalPlacement))
    }

    private func verticalPlacement(for translationHeight: CGFloat, height: CGFloat) -> Double {
        let range = verticalRange(in: height)
        let travelDistance = max(range.max - range.min, 1)
        let nextPlacement = dragStartVerticalPlacement + Double(translationHeight / travelDistance)
        return min(max(nextPlacement, 0), 1)
    }

    private func verticalRange(in height: CGFloat) -> (min: CGFloat, max: CGFloat) {
        let minY = min(verticalInset, height * 0.5)
        let maxY = max(height - verticalInset, minY)
        return (minY, maxY)
    }

    private func handleDragChanged(_ value: DragGesture.Value, in size: CGSize) {
        if !isDraggingSwitcher {
            let horizontalDistance = abs(value.translation.width)
            let verticalDistance = abs(value.translation.height)
            guard max(horizontalDistance, verticalDistance) > longPressMaximumDistance else { return }
            isDraggingSwitcher = true
            dragStartVerticalPlacement = verticalPlacement
        }

        withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.82)) {
            verticalPlacement = verticalPlacement(for: value.translation.height, height: size.height)
        }
        onDragChanged(value.translation.width, size.width)
    }

    private func handleDragEnded(_ value: DragGesture.Value, in size: CGSize) {
        guard isDraggingSwitcher else {
            onPressing(false)
            return
        }

        isDraggingSwitcher = false
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            verticalPlacement = verticalPlacement(for: value.translation.height, height: size.height)
        }
        onDragEnded(value.translation.width, value.predictedEndTranslation.width, size.width)
    }
}

private struct SwitcherRemovePopover: View {
    let choices: [SocialTab]
    let arrowEdge: Edge
    let onRemoveTab: (SocialTab) -> Void

    var body: some View {
        contents
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
            }
            .overlay(alignment: arrowAlignment) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(.regularMaterial)
                    .frame(width: 14, height: 14)
                    .rotationEffect(.degrees(45))
                    .offset(x: arrowOffset)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.primary.opacity(0.08), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var contents: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Remove a tab?")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 6)

            ForEach(choices) { tab in
                Button(role: .destructive) {
                    onRemoveTab(tab)
                } label: {
                    HStack(spacing: 10) {
                        Text(tab.removeActionTitle)
                        Spacer(minLength: 12)
                        Image(systemName: "trash")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 6)
    }

    private var arrowAlignment: Alignment {
        arrowEdge == .leading ? .leading : .trailing
    }

    private var arrowOffset: CGFloat {
        arrowEdge == .leading ? -5 : 5
    }
}

private struct LongPressRecognizer: UIViewRepresentable {
    let minimumPressDuration: TimeInterval
    let allowableMovement: CGFloat
    let onBegan: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBegan: onBegan)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let recognizer = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress))
        recognizer.minimumPressDuration = minimumPressDuration
        recognizer.allowableMovement = allowableMovement
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = context.coordinator
        view.addGestureRecognizer(recognizer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onBegan = onBegan
        guard let recognizer = uiView.gestureRecognizers?.compactMap({ $0 as? UILongPressGestureRecognizer }).first else {
            return
        }
        recognizer.minimumPressDuration = minimumPressDuration
        recognizer.allowableMovement = allowableMovement
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onBegan: () -> Void

        init(onBegan: @escaping () -> Void) {
            self.onBegan = onBegan
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            onBegan()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

private extension View {
    @ViewBuilder
    func interactiveLiquidGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }
}

private extension SocialTab {
    var removeActionTitle: String {
        switch self {
        case .x: return "Remove X / Twitter Tab"
        case .bluesky: return "Remove Bluesky Tab"
        }
    }
}

// MARK: - Duration formatting

private func formatDuration(_ seconds: TimeInterval) -> String {
    let totalSeconds = max(0, Int(seconds.rounded()))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let secs = totalSeconds % 60
    let paddedMinutes = twoDigitString(minutes)
    let paddedSeconds = twoDigitString(secs)
    if hours > 0 {
        return "\(hours):\(paddedMinutes):\(paddedSeconds)"
    } else {
        return "\(minutes):\(paddedSeconds)"
    }
}

private func twoDigitString(_ value: Int) -> String {
    value < 10 ? "0\(value)" : "\(value)"
}

#Preview {
    ContentView(requestedURL: .constant(URL.required(string: "https://x.com/notifications")), activeTab: .x)
        .environmentObject(OnScreenTimeTracker())
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        _ = uiViewController
        _ = context
    }
}

final class ShakeDetector: ObservableObject {
    @Published private(set) var shakeCount: Int = 0

    private let motionManager = CMMotionManager()
    private var lastShakeAt: Date = .distantPast
    private let shakeThreshold: Double = 2.2
    private let shakeCooldown: TimeInterval = 1.0

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        guard !motionManager.isDeviceMotionActive else { return }

        motionManager.deviceMotionUpdateInterval = 1.0 / 35.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let accel = motion.userAcceleration
            let magnitude = sqrt((accel.x * accel.x) + (accel.y * accel.y) + (accel.z * accel.z))
            guard magnitude >= self.shakeThreshold else { return }

            let now = Date()
            guard now.timeIntervalSince(self.lastShakeAt) >= self.shakeCooldown else { return }
            self.lastShakeAt = now
            self.shakeCount += 1
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }
}

// MARK: - WebView Wrapper

struct WebView: UIViewRepresentable {
    private static let requestTimeout: TimeInterval = 30
    let url: URL
    @Binding var isLoading: Bool
    @Binding var lastErrorDescription: String?
    let activeTab: SocialTab
    let onOpenURLInTab: (URL, SocialTab) -> Void

    typealias UIViewType = WKWebView

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        context.coordinator.updateParent(self)
        context.coordinator.recordProgrammaticRequest(url)
        webView.customUserAgent = activeTab.userAgent
        load(url, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.updateParent(self)
        guard context.coordinator.shouldApplyProgrammaticRequest(url) else { return }
        context.coordinator.recordProgrammaticRequest(url)
        load(url, in: webView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, activeTab: activeTab)
    }

    private func load(_ url: URL, in webView: WKWebView) {
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: Self.requestTimeout))
    }
}

final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    private static let webSchemes: Set<String> = ["http", "https"]
    private static let safeInlineSchemes: Set<String> = ["about", "data"]

    private var parent: WebView
    private let activeTab: SocialTab
    private var didInstallContentRules: Bool = false
    private var lastProgrammaticRequestURL: URL?

    init(parent: WebView, activeTab: SocialTab) {
        self.parent = parent
        self.activeTab = activeTab
    }

    // swiftlint:disable:next implicitly_unwrapped_optional
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        DispatchQueue.main.async { [weak self] in
            self?.parent.isLoading = true
        }
    }

    // swiftlint:disable:next implicitly_unwrapped_optional
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        handleNavigationFailure(error, prefix: "Navigation failed")
    }

    // swiftlint:disable:next implicitly_unwrapped_optional
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        handleNavigationFailure(error, prefix: "Provisional navigation failed")
    }

    // swiftlint:disable:next implicitly_unwrapped_optional
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        #if DEBUG
        print("Navigation finished: \(webView.url?.absoluteString ?? "<nil>")")
        #endif

        if !didInstallContentRules {
            didInstallContentRules = true
            ContentBlocker.installRuleList(into: webView, identifier: activeTab.contentBlockerIdentifier, rulesJSON: activeTab.contentBlockerRulesJSON, completion: nil)
        }
        DispatchQueue.main.async { [weak self] in
            self?.parent.lastErrorDescription = nil
            self?.parent.isLoading = false
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow)
            return
        }

        if let mapped = Self.mapSafariBounceURL(url) {
            webView.load(URLRequest(url: mapped))
            decisionHandler(.cancel)
            return
        }

        if Self.webSchemes.contains(scheme) {
            if shouldRedirectHomeTimelineToNotifications(url) {
                recordProgrammaticRequest(activeTab.startURL)
                webView.load(URLRequest(url: activeTab.startURL))
                decisionHandler(.cancel)
                return
            }
            handleHTTPNavigation(url, action: navigationAction, decisionHandler: decisionHandler)
            return
        }

        if Self.safeInlineSchemes.contains(scheme) {
            decisionHandler(.allow)
            return
        }

        if let mapped = activeTab.mapDeepLinkToHTTPS(url) {
            webView.load(URLRequest(url: mapped))
            decisionHandler(.cancel)
            return
        }

        if EchoURLScheme.appSchemes.contains(scheme) {
            switch IncomingURLRouter.route(url) {
            case .openInApp(let mapped, let tab):
                if tab == activeTab {
                    webView.load(URLRequest(url: mapped))
                } else {
                    parent.onOpenURLInTab(mapped, tab)
                }

            case .openExternal(let externalURL):
                Self.openExternal(externalURL)

            case .ignore:
                break
            }
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else {
            return nil
        }

        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            webView.load(navigationAction.request)
            return nil
        }

        if Self.webSchemes.contains(scheme), !isInternalHost(url) {
            routeExternalNavigation(url)
        } else {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

private extension Coordinator {
    func updateParent(_ parent: WebView) {
        self.parent = parent
    }

    func shouldApplyProgrammaticRequest(_ url: URL) -> Bool {
        lastProgrammaticRequestURL?.absoluteString != url.absoluteString
    }

    func recordProgrammaticRequest(_ url: URL) {
        lastProgrammaticRequestURL = url
    }

    func handleNavigationFailure(_ error: any Error, prefix: String) {
        if Self.shouldIgnoreNavigationError(error) {
            #if DEBUG
            print("Ignoring expected navigation cancellation: \(error.localizedDescription)")
            #endif
            return
        }
        #if DEBUG
        print("\(prefix): \(error.localizedDescription)")
        #endif
        DispatchQueue.main.async { [weak self] in
            self?.parent.lastErrorDescription = error.localizedDescription
            self?.parent.isLoading = false
        }
    }

    func handleHTTPNavigation(_ url: URL, action: WKNavigationAction, decisionHandler: @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let isUserTap = action.navigationType == .linkActivated
        let isMainFrame = action.targetFrame?.isMainFrame ?? true

        guard isUserTap && isMainFrame else {
            decisionHandler(.allow)
            return
        }

        if isInternalHost(url) {
            decisionHandler(.allow)
        } else {
            routeExternalNavigation(url)
            decisionHandler(.cancel)
        }
    }

    func routeExternalNavigation(_ url: URL) {
        switch IncomingURLRouter.route(url) {
        case .openInApp(let mapped, let tab):
            parent.onOpenURLInTab(mapped, tab)

        case .openExternal(let externalURL):
            Coordinator.openExternal(externalURL)

        case .ignore:
            Coordinator.openExternal(url)
        }
    }

    func isInternalHost(_ url: URL) -> Bool {
        activeTab.hasCanonicalHost(for: url)
    }

    func shouldRedirectHomeTimelineToNotifications(_ url: URL) -> Bool {
        guard isInternalHost(url) else { return false }
        let normalizedPath = Self.normalizePath(url.path)
        return normalizedPath == "/home" || normalizedPath == "/i/timeline"
    }

    static func normalizePath(_ path: String) -> String {
        let lowercased = path.lowercased()
        guard lowercased.count > 1, lowercased.hasSuffix("/") else {
            return lowercased
        }
        return String(lowercased.dropLast())
    }

    static func shouldIgnoreNavigationError(_ error: any Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }
        // WebKitErrorDomain code 102 is frame-load interrupted by a policy change.
        if nsError.domain == WKError.errorDomain,
           nsError.code == 102 {
            return true
        }
        return false
    }
}

extension Coordinator {
    static func openExternal(_ url: URL) {
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    static func mapSafariBounceURL(_ url: URL) -> URL? {
        IncomingURLRouter.mapSafariBounceURL(url)
    }

    static func mapTwitterDeepLinkToHTTPS(url: URL) -> URL? {
        IncomingURLRouter.mapTwitterDeepLinkToHTTPS(url: url)
    }

    static func mapEchoDotAppToHTTPS(url: URL) -> URL? {
        IncomingURLRouter.mapEchoDotAppToHTTPS(url: url)
    }
}

// MARK: - Content Blocker Management

enum ContentBlocker {
    static func installRuleList(into webView: WKWebView, identifier: String, rulesJSON: String, completion: ((Bool) -> Void)? = nil) {
        let store = WKContentRuleListStore.default()

        store?.lookUpContentRuleList(forIdentifier: identifier) { existing, error in
            if let error = error {
                #if DEBUG
                print("Rule list lookup error: \(error.localizedDescription)")
                #endif
            }
            if let existing = existing {
                webView.configuration.userContentController.add(existing)
                completion?(true)
                return
            }

            store?.compileContentRuleList(forIdentifier: identifier,
                                          encodedContentRuleList: rulesJSON) { compiled, error in
                if let error = error {
                    #if DEBUG
                    print("Rule list compile error: \(error.localizedDescription)")
                    #endif
                }
                guard let compiled = compiled else { completion?(false); return }
                webView.configuration.userContentController.add(compiled)
                completion?(true)
            }
        }
    }

    static let blueskyRulesJSON = """
    [
      {
        "trigger": { "url-filter": ".*", "if-domain": ["cope.works", "www.cope.works"] },
        "action": { "type": "css-display-none", "selector": "[data-testid='followingFeedPage']" }
      },
      {
        "trigger": { "url-filter": ".*", "if-domain": ["cope.works", "www.cope.works"] },
        "action": { "type": "css-display-none", "selector": "[aria-label='Home']" }
      },
      {
        "trigger": { "url-filter": ".*", "if-domain": ["cope.works", "www.cope.works"] },
        "action": { "type": "css-display-none", "selector": "[aria-label='Lists']" }
      },
      {
        "trigger": { "url-filter": ".*", "if-domain": ["cope.works", "www.cope.works"] },
        "action": { "type": "css-display-none", "selector": "[aria-label='Feeds']" }
      }
    ]
    """

    static let xRulesJSON = """
    [
      {
        "trigger": { "url-filter": ".*", "if-domain": ["x.com", "twitter.com"] },
        "action": { "type": "css-display-none", "selector": "[aria-label='Home']" }
      },
      {
        "trigger": { "url-filter": ".*", "if-domain": ["x.com", "twitter.com"] },
        "action": { "type": "css-display-none", "selector": "[aria-label='SuperGrok']" }
      },
      {
        "trigger": { "url-filter": ".*", "if-domain": ["x.com", "twitter.com"] },
        "action": { "type": "css-display-none", "selector": "[aria-label='Grok']" }
      },
      {
        "trigger": { "url-filter": ".*", "if-domain": ["x.com", "twitter.com"] },
        "action": { "type": "css-display-none", "selector": "[aria-label='Premium']" }
      },
      {
        "trigger": { "url-filter": ".*", "if-domain": ["x.com", "twitter.com"] },
        "action": { "type": "css-display-none", "selector": "[aria-label='Communities']" }
      },
      {
        "trigger": { "url-filter": ".*", "if-domain": ["x.com", "twitter.com"] },
        "action": { "type": "css-display-none", "selector": "[aria-label='Timeline: Your Home Timeline']" }
      },
      {
        "trigger": { "url-filter": ".*", "if-domain": ["x.com", "twitter.com"] },
        "action": { "type": "css-display-none", "selector": "[aria-label='Timeline: Explore']" }
      }
    ]
    """
}
