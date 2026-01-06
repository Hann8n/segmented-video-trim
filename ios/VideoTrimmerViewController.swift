//
//  VideoTrimmerViewController.swift
//  VideoTrim
//
//  Created by Duc Trung Mai on 20/5/25.
//

import UIKit
import AVKit
import React

extension CMTime {
    var displayString: String {
        // Round to 1 decimal place to match segments mechanism (toFixed(1))
        // Use standard rounding (round half up) to match JavaScript's toFixed(1)
        let roundedSeconds = (seconds * 10).rounded() / 10.0
        let minutes = Int(roundedSeconds) / 60
        let seconds = Int(roundedSeconds) % 60
        let decimal = Int((roundedSeconds.truncatingRemainder(dividingBy: 1.0)) * 10)
        
        if minutes > 0 {
            // Format: "M:SS.D" (no leading zeros on minutes, 1 decimal place)
            return String(format: "%d:%02d.%d", minutes, seconds, decimal)
        } else {
            // Format: "S.D" (no leading zeros, 1 decimal place)
            return String(format: "%d.%d", seconds, decimal)
        }
    }
}

@available(iOS 13.0, *)
class VideoTrimmerViewController: UIViewController {
    
    // Helper to find the correct bundle for resources
    // When using 'resources' in podspec, files are copied to main bundle
    // When using 'resource_bundles', files are in a separate bundle
    private static var resourceBundle: Bundle? = {
        // Check main bundle first (most common for 'resources')
        if Bundle.main.path(forResource: "close_fill", ofType: "png") != nil {
            return Bundle.main
        }
        // Check pod bundle (for 'resource_bundles' or if resources end up there)
        let podBundle = Bundle(for: VideoTrimmerViewController.self)
        if podBundle.path(forResource: "close_fill", ofType: "png") != nil {
            return podBundle
        }
        // Default to main bundle
        return Bundle.main
    }()
    var asset: AVAsset? {
        didSet {
            if let _ = asset {
                setupPlayerController()
                setupVideoTrimmer()
                setupTimeObserver()
                updateLabels()
            }
        }
    }
    private var maximumDuration: Double?
    private var minimumDuration: Double?
    // Button text variables kept for API compatibility but not used (icons are used instead)
    private var cancelButtonText = "Cancel"
    private var saveButtonText = "Save"
    var cancelBtnClicked: (() -> Void)?
    var saveBtnClicked: ((CMTimeRange) -> Void)?
    private var enableHapticFeedback = true
    private var zoomOnWaitingDuration: Double = 5.0 // Default: 5 seconds
    private var autoplay = true
    
    // New color properties
    private var trimmerColor: UIColor = UIColor.systemYellow
    private var handleIconColor: UIColor = UIColor.black
    
    private let playerController = AVPlayerViewController()
    private var trimmer: VideoTrimmer!
    private var timingStackView: UIStackView!
    private var leadingTrimLabel: UILabel!
    private var currentTimeLabel: UILabel!
    private var trailingTrimLabel: UILabel!
    private var cancelBtn: UIButton!
    private var playBtn: UIButton!
    private let loadingIndicator = UIActivityIndicatorView()
    private var saveBtn: UIButton!
    private let playIcon = UIImage(systemName: "play.fill")
    private let pauseIcon = UIImage(systemName: "pause.fill")
    private let audioBannerView = UIImage(systemName: "airpodsmax")
    private lazy var cancelIcon: UIImage? = {
        guard let bundle = VideoTrimmerViewController.resourceBundle else {
            return UIImage(named: "close_fill")
        }
        // Try with extension first
        if let image = UIImage(named: "close_fill.png", in: bundle, compatibleWith: nil) {
            return image
        }
        // Try without extension
        if let image = UIImage(named: "close_fill", in: bundle, compatibleWith: nil) {
            return image
        }
        // Fallback to main bundle
        return UIImage(named: "close_fill")
    }()
    private lazy var saveIcon: UIImage? = {
        guard let bundle = VideoTrimmerViewController.resourceBundle else {
            return UIImage(named: "arrow_right_fill")
        }
        // Try with extension first
        if let image = UIImage(named: "arrow_right_fill.png", in: bundle, compatibleWith: nil) {
            return image
        }
        // Try without extension
        if let image = UIImage(named: "arrow_right_fill", in: bundle, compatibleWith: nil) {
            return image
        }
        // Fallback to main bundle
        return UIImage(named: "arrow_right_fill")
    }()
    private var player: AVPlayer! { playerController.player }
    private var timeObserverToken: Any?
    private var jumpToPositionOnLoad: Double = 0;
    private var headerText: String?
    private var headerTextSize = 16
    private var headerTextColor: Double?
    private var headerView: UIView?
    
    var isSeekInProgress: Bool = false  // Marker
    private var chaseTime = CMTime.zero
    private var preferredFrameRate: Float = 23.98
    
    public func onAssetFailToLoad() {
        loadingIndicator.stopAnimating()
        loadingIndicator.alpha = 0
        
        let errorImageView = UIImageView(image: UIImage(systemName: "exclamationmark.triangle.fill"))
        errorImageView.tintColor = .systemYellow
        errorImageView.translatesAutoresizingMaskIntoConstraints = false
        errorImageView.alpha = 0
        view.addSubview(errorImageView)
        
        NSLayoutConstraint.activate([
            errorImageView.widthAnchor.constraint(equalToConstant: 36),
            errorImageView.heightAnchor.constraint(equalToConstant: 36),
            errorImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorImageView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        
        UIView.animate(withDuration: 0.25, animations: {
            errorImageView.alpha = 1
        })
    }
    
    // MARK: - Input
    @objc private func didBeginTrimmingFromStart(_ sender: VideoTrimmer) {
        leadingTrimLabel.isHidden = false
        trailingTrimLabel.isHidden = false
        handleBeforeProgressChange()
    }
    
    @objc private func leadingGrabberChanged(_ sender: VideoTrimmer) {
        handleProgressChanged(time: trimmer.selectedRange.start)
    }
    
    @objc private func didEndTrimmingFromStart(_ sender: VideoTrimmer) {
        leadingTrimLabel.isHidden = true
        trailingTrimLabel.isHidden = true
        handleTrimmingEnd(true)
    }
    
    @objc private func didBeginTrimmingFromEnd(_ sender: VideoTrimmer) {
        leadingTrimLabel.isHidden = false
        trailingTrimLabel.isHidden = false
        handleBeforeProgressChange()
    }
    
    @objc private func trailingGrabberChanged(_ sender: VideoTrimmer) {
        handleProgressChanged(time: trimmer.selectedRange.end)
    }
    
    @objc private func didEndTrimmingFromEnd(_ sender: VideoTrimmer) {
        leadingTrimLabel.isHidden = true
        trailingTrimLabel.isHidden = true
        handleTrimmingEnd(false)
    }
    
    @objc private func didBeginScrubbing(_ sender: VideoTrimmer) {
        handleBeforeProgressChange()
    }
    
    @objc private func didEndScrubbing(_ sender: VideoTrimmer) {
        updateLabels()
        // Resume autoplay after scrubbing if enabled
        if autoplay {
            if CMTimeCompare(trimmer.progress, trimmer.selectedRange.end) != -1 {
                trimmer.progress = trimmer.selectedRange.start
                seek(to: trimmer.progress)
            }
            player.play()
            setPlayBtnIcon()
        }
    }
    
    @objc private func progressDidChanged(_ sender: VideoTrimmer) {
        handleProgressChanged(time: trimmer.progress)
    }
    
    // MARK: - Private
    private func updateLabels() {
        leadingTrimLabel.text = trimmer.selectedRange.start.displayString
        currentTimeLabel.text = trimmer.selectedRange.duration.displayString
        trailingTrimLabel.text = trimmer.selectedRange.end.displayString
    }
    
    private func handleBeforeProgressChange() {
        updateLabels()
        player.pause()
        setPlayBtnIcon()
    }
    
    private func handleProgressChanged(time: CMTime) {
        updateLabels()
        seek(to: time)
    }
    
    private func handleTrimmingEnd(_ start: Bool) {
        self.trimmer.progress = start ? trimmer.selectedRange.start : trimmer.selectedRange.end
        updateLabels()
        seek(to: trimmer.progress)
        // Resume autoplay after trimming if enabled
        if autoplay {
            if CMTimeCompare(trimmer.progress, trimmer.selectedRange.end) != -1 {
                trimmer.progress = trimmer.selectedRange.start
                seek(to: trimmer.progress)
            }
            player.play()
            setPlayBtnIcon()
        }
    }
    
    // MARK: - UIViewController
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupView()
        setupButtons()
        setupTimeLabels()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // if asset has been initialized
        guard let _ = asset else { return }
        player.pause()
        
        // Clean up the observer
        player.removeObserver(self, forKeyPath: "status")
        
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        
        playerController.player = nil
        playerController.dismiss(animated: false, completion: nil)
    }
    
    public func pausePlayer() {
        player.pause()
        setPlayBtnIcon()
    }
    
    @objc private func togglePlay(sender: UIButton) {
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            if CMTimeCompare(trimmer.progress, trimmer.selectedRange.end) != -1 {
                trimmer.progress = trimmer.selectedRange.start
                self.seek(to: trimmer.progress)
            }
            player.play()
        }
        
        setPlayBtnIcon()
    }
    
    @objc private func onSaveBtnClicked() {
        saveBtnClicked?(trimmer.selectedRange)
    }
    
    @objc private func onCancelBtnClicked() {
        cancelBtnClicked?()
    }
    
    // MARK: - Color Update Methods
    private func applyTrimmerColors() {
        guard let trimmer = trimmer else { return }
        
        // Apply trimmer color to the thumb view
        trimmer.thumbView.updateTrimmerColor(trimmerColor)
        
        // Apply handle icon color to the chevron image views
        trimmer.thumbView.updateHandleIconColor(handleIconColor)
    }
    
    // MARK: - Setup Methods
    private func setupView() {
        self.overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black // need to have this otherwise during animation the background of this VC is still white in white theme
        // Make sure the view doesn't have any extra spacing that creates black bars
        
        if let headerText = headerText {
            headerView = UIView()
            headerView!.translatesAutoresizingMaskIntoConstraints = false
            headerView!.backgroundColor = .clear // Make header transparent
            view.addSubview(headerView!)
            let headerTextView = UILabel()
            headerTextView.text = headerText
            headerTextView.textAlignment = .center
            headerTextView.textColor = RCTConvert.uiColor(headerTextColor) ?? .white
            headerTextView.font = UIFont.systemFont(ofSize: CGFloat(headerTextSize))
            headerTextView.translatesAutoresizingMaskIntoConstraints = false
            headerView!.addSubview(headerTextView)
            
            NSLayoutConstraint.activate([
                // HeaderView constraints
                headerView!.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                headerView!.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                headerView!.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                headerView!.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
                
                // HeaderText constraints
                headerTextView.topAnchor.constraint(equalTo: headerView!.topAnchor),
                headerTextView.bottomAnchor.constraint(equalTo: headerView!.bottomAnchor),
                headerTextView.leadingAnchor.constraint(equalTo: headerView!.leadingAnchor),
                headerTextView.trailingAnchor.constraint(equalTo: headerView!.trailingAnchor),
            ])
            
            view.layoutIfNeeded() // layout after activate constraints, otherwise headerView height = screen height, which leads to playerViewController is missing at runtime
        }
    }
    
    private func setupButtons() {
        // Match create.tsx sizing: cancel = 26, save = 30
        let cancelIconSize: CGFloat = 26
        let saveIconSize: CGFloat = 30
        let resizedCancelIcon = cancelIcon?.resize(to: CGSize(width: cancelIconSize, height: cancelIconSize), scale: UIScreen.main.scale)
        let resizedSaveIcon = saveIcon?.resize(to: CGSize(width: saveIconSize, height: saveIconSize), scale: UIScreen.main.scale)
        
        // Cancel button: positioned at top left like create.tsx
        cancelBtn = UIButton.createButton(image: resizedCancelIcon, tintColor: nil, target: self, action: #selector(onCancelBtnClicked))
        cancelBtn.backgroundColor = .clear
        cancelBtn.isOpaque = false
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        // Ensure button is above video in z-order
        view.addSubview(cancelBtn)
        
        // Play button: hidden since we use tap gesture on video
        playBtn = UIButton.createButton(image: playIcon, tintColor: .white, target: self, action: #selector(togglePlay(sender:)))
        playBtn.alpha = 0
        playBtn.isEnabled = false
        playBtn.isHidden = true
        playBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(playBtn)
        
        // Save button: positioned at top right like create.tsx
        saveBtn = UIButton.createButton(image: resizedSaveIcon, tintColor: nil, target: self, action: #selector(onSaveBtnClicked))
        saveBtn.backgroundColor = .clear
        saveBtn.isOpaque = false
        saveBtn.alpha = 0
        saveBtn.isEnabled = false
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        // Ensure button is above video in z-order
        view.addSubview(saveBtn)
        
        // Loading indicator: positioned in center (will be replaced by play button when ready)
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingIndicator)
        
        // Match create.tsx positioning: top = safeAreaLayoutGuide.topAnchor + 4
        // Cancel button: left = 4, container = 44x44
        // Save button: right = 4, container = 44x44
        NSLayoutConstraint.activate([
            // Cancel button at top left - minimal spacing
            cancelBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            cancelBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            cancelBtn.widthAnchor.constraint(equalToConstant: 44),
            cancelBtn.heightAnchor.constraint(equalToConstant: 44),
            
            // Save button at top right - minimal spacing
            saveBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            saveBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            saveBtn.widthAnchor.constraint(equalToConstant: 44),
            saveBtn.heightAnchor.constraint(equalToConstant: 44),
            
            // Play button hidden (using tap gesture instead)
            playBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            playBtn.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            // Loading indicator in center (temporary)
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        
        loadingIndicator.startAnimating()
    }
    
    private func setupTimeLabels() {
        leadingTrimLabel = UILabel.createLabel(textAlignment: .left, textColor: .white)
        leadingTrimLabel.text = "00:00.000"
        leadingTrimLabel.isHidden = true
        
        // Duration label with white pill background - wrap in container for padding
        currentTimeLabel = UILabel()
        currentTimeLabel.text = "00:00.000"
        currentTimeLabel.font = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .semibold)
        currentTimeLabel.textColor = .black
        currentTimeLabel.textAlignment = .center
        currentTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Container view with white pill background
        let pillContainer = UIView()
        pillContainer.backgroundColor = .white
        pillContainer.layer.cornerRadius = 12
        pillContainer.clipsToBounds = true
        pillContainer.translatesAutoresizingMaskIntoConstraints = false
        pillContainer.addSubview(currentTimeLabel)
        
        // Add padding constraints - pill container sizes to label content
        NSLayoutConstraint.activate([
            currentTimeLabel.topAnchor.constraint(equalTo: pillContainer.topAnchor, constant: 4),
            currentTimeLabel.bottomAnchor.constraint(equalTo: pillContainer.bottomAnchor, constant: -4),
            currentTimeLabel.leadingAnchor.constraint(equalTo: pillContainer.leadingAnchor, constant: 12),
            currentTimeLabel.trailingAnchor.constraint(equalTo: pillContainer.trailingAnchor, constant: -12),
            pillContainer.heightAnchor.constraint(equalToConstant: 24),
            // Ensure pill container doesn't expand beyond its content
            pillContainer.widthAnchor.constraint(equalTo: currentTimeLabel.widthAnchor, constant: 24) // 12pt padding on each side
        ])
        
        trailingTrimLabel = UILabel.createLabel(textAlignment: .right, textColor: .white)
        trailingTrimLabel.text = "00:00.000"
        trailingTrimLabel.isHidden = true
        
        // Create a container for the center pill that won't expand
        let centerContainer = UIView()
        centerContainer.translatesAutoresizingMaskIntoConstraints = false
        centerContainer.addSubview(pillContainer)
        
        // Center the pill container within its parent
        NSLayoutConstraint.activate([
            pillContainer.centerXAnchor.constraint(equalTo: centerContainer.centerXAnchor),
            pillContainer.centerYAnchor.constraint(equalTo: centerContainer.centerYAnchor),
            pillContainer.topAnchor.constraint(greaterThanOrEqualTo: centerContainer.topAnchor),
            pillContainer.bottomAnchor.constraint(lessThanOrEqualTo: centerContainer.bottomAnchor)
        ])
        
        // Set content hugging priority so center container doesn't expand
        centerContainer.setContentHuggingPriority(.required, for: .horizontal)
        centerContainer.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        timingStackView = UIStackView(arrangedSubviews: [leadingTrimLabel, centerContainer, trailingTrimLabel])
        timingStackView.axis = .horizontal
        timingStackView.alignment = .center
        timingStackView.distribution = .equalSpacing
        timingStackView.spacing = UIStackView.spacingUseSystem
        // Timing labels will be positioned over the trimmer, so add to player view instead
        timingStackView.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private func setupVideoTrimmer() {
        trimmer = VideoTrimmer()
        trimmer.asset = asset
        trimmer.minimumDuration = CMTime(seconds: 1, preferredTimescale: 600)
        trimmer.enableHapticFeedback = enableHapticFeedback
        trimmer.zoomOnWaitingDuration = zoomOnWaitingDuration
        
        if let maxDuration = maximumDuration {
            trimmer.maximumDuration = CMTime(seconds: max(1, Double(maxDuration)), preferredTimescale: 600)
            if trimmer.maximumDuration > asset!.duration {
                trimmer.maximumDuration = asset!.duration
            }
            trimmer.selectedRange = CMTimeRange(start: .zero, end: trimmer.maximumDuration)
        }
        
        if let minDuration = minimumDuration {
            trimmer.minimumDuration = CMTime(seconds: max(1, Double(minDuration)), preferredTimescale: 600)
        }
        
        trimmer.addTarget(self, action: #selector(didBeginScrubbing(_:)), for: VideoTrimmer.didBeginScrubbing)
        trimmer.addTarget(self, action: #selector(didEndScrubbing(_:)), for: VideoTrimmer.didEndScrubbing)
        trimmer.addTarget(self, action: #selector(progressDidChanged(_:)), for: VideoTrimmer.progressChanged)
        
        trimmer.addTarget(self, action: #selector(didBeginTrimmingFromStart(_:)), for: VideoTrimmer.didBeginTrimmingFromStart)
        trimmer.addTarget(self, action: #selector(leadingGrabberChanged(_:)), for: VideoTrimmer.leadingGrabberChanged)
        trimmer.addTarget(self, action: #selector(didEndTrimmingFromStart(_:)), for: VideoTrimmer.didEndTrimmingFromStart)
        
        trimmer.addTarget(self, action: #selector(didBeginTrimmingFromEnd(_:)), for: VideoTrimmer.didBeginTrimmingFromEnd)
        trimmer.addTarget(self, action: #selector(trailingGrabberChanged(_:)), for: VideoTrimmer.trailingGrabberChanged)
        trimmer.addTarget(self, action: #selector(didEndTrimmingFromEnd(_:)), for: VideoTrimmer.didEndTrimmingFromEnd)
        trimmer.alpha = 0
        // Add trimmer as overlay on player view
        playerController.view.addSubview(trimmer)
        trimmer.translatesAutoresizingMaskIntoConstraints = false
        
        // Add timing labels as overlay on trimmer
        playerController.view.addSubview(timingStackView)
        
        NSLayoutConstraint.activate([
            // Trimmer overlaid at bottom of video
            trimmer.leadingAnchor.constraint(equalTo: playerController.view.leadingAnchor),
            trimmer.trailingAnchor.constraint(equalTo: playerController.view.trailingAnchor),
            trimmer.bottomAnchor.constraint(equalTo: playerController.view.bottomAnchor, constant: -16),
            trimmer.heightAnchor.constraint(equalToConstant: 56),
            
            // Timing labels above trimmer
            timingStackView.leadingAnchor.constraint(equalTo: playerController.view.leadingAnchor, constant: 16),
            timingStackView.trailingAnchor.constraint(equalTo: playerController.view.trailingAnchor, constant: -16),
            timingStackView.bottomAnchor.constraint(equalTo: trimmer.topAnchor, constant: -8)
        ])
        
        UIView.animate(withDuration: 0.25, animations: {
            self.trimmer.alpha = 1
        })
        
        // Apply the trimmer colors
        applyTrimmerColors()
    }
    
    private func setupPlayerController() {
        playerController.showsPlaybackControls = false
        if #available(iOS 16.0, *) {
            playerController.allowsVideoFrameAnalysis = false
        }
        playerController.player = AVPlayer()
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset!))
        
        // Add observer for player status
        player.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
        
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        addChild(playerController)
        view.addSubview(playerController.view)
        // Send video to back so buttons and header appear on top
        view.sendSubviewToBack(playerController.view)
        playerController.view.translatesAutoresizingMaskIntoConstraints = false
        
        // Determine if device is tall enough to position video below status bar
        // iPhone X and later (with notch) have taller screens, older iPhones are shorter
        let screenHeight = UIScreen.main.bounds.height
        let isTallDevice = screenHeight >= 812 // iPhone X and later are 812pt or taller
        
        // Set up constraints to position video below status bar on tall devices, centered on short devices
        NSLayoutConstraint.activate([
            // Player view: flush with sides, fill width
            playerController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // Maintain aspect ratio (required priority)
            playerController.view.heightAnchor.constraint(equalTo: playerController.view.widthAnchor, multiplier: 16.0/9.0)
        ])
        
        if isTallDevice {
            // On taller devices: position below status bar (safe area top)
            let topConstraint = playerController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
            topConstraint.priority = UILayoutPriority(1000)
            topConstraint.isActive = true
        } else {
            // On shorter devices: center vertically
            let centerYConstraint = playerController.view.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            centerYConstraint.priority = UILayoutPriority(1000)
            centerYConstraint.isActive = true
            
            // But still allow extending above safe area if needed
            let topConstraint = playerController.view.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor)
            topConstraint.priority = UILayoutPriority(750)
            topConstraint.isActive = true
        }
        
        // Bottom constraint to prevent video from going off screen
        let bottomConstraint = playerController.view.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor)
        bottomConstraint.priority = UILayoutPriority(1000)
        bottomConstraint.isActive = true
        
        // Set video gravity to fit within view while maintaining aspect ratio (no cropping)
        playerController.videoGravity = .resizeAspect
        
        // Add tap gesture to video view for play/pause
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(videoViewTapped))
        playerController.view.addGestureRecognizer(tapGesture)
        playerController.view.isUserInteractionEnabled = true
    }
    
    @objc private func videoViewTapped() {
        togglePlay(sender: playBtn)
    }
    
    private func setupTimeObserver() {
        // Periodic observer for UI updates and looping check - check more frequently for better looping precision
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 60), queue: .main) { [weak self] time in
            guard let self = self else { return }
            
            if self.player.timeControlStatus != .playing {
                return
            }
            
            // Check if we've reached or passed the end of selected range
            if CMTimeCompare(time, self.trimmer.selectedRange.end) >= 0 {
                // Immediately loop back to start
                self.trimmer.progress = self.trimmer.selectedRange.start
                self.player.seek(to: self.trimmer.selectedRange.start, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                    guard let self = self else { return }
                    // Ensure playback continues
                    if self.player.timeControlStatus != .playing {
                        self.player.play()
                    }
                }
            } else {
                // Update progress only if within selected range
                self.trimmer.progress = time
            }
            
            currentTimeLabel.text = trimmer.selectedRange.duration.displayString
            
            self.setPlayBtnIcon()
        }
    }
    
    private func setPlayBtnIcon() {
        self.playBtn.setImage(self.player.timeControlStatus == .playing ? self.pauseIcon : self.playIcon, for: .normal)
    }
    
    private func updateSaveButtonCornerRadius() {
        // No longer needed - buttons are just icons now
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateSaveButtonCornerRadius()
    }
    
    // ====Smoother seek
    public func seek(to time: CMTime) {
        seekSmoothlyToTime(newChaseTime: time)
    }
    
    private func seekSmoothlyToTime(newChaseTime: CMTime) {
        if CMTimeCompare(newChaseTime, chaseTime) != 0 {
            chaseTime = newChaseTime
            
            if !isSeekInProgress {
                trySeekToChaseTime()
            }
        }
    }
    
    private func trySeekToChaseTime() {
        guard player?.status == .readyToPlay else { return }
        actuallySeekToTime()
    }
    
    private func actuallySeekToTime() {
        isSeekInProgress = true
        let seekTimeInProgress = chaseTime
        
        player?.seek(to: seekTimeInProgress, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let `self` = self else { return }
            
            if CMTimeCompare(seekTimeInProgress, self.chaseTime) == 0 {
                self.isSeekInProgress = false
            } else {
                self.trySeekToChaseTime()
            }
        }
    }
    
  public func configure(config: NSDictionary) {
    if let maxDurationValue = config["maxDuration"] {
      if let maxDuration = maxDurationValue as? Double, maxDuration > 0 {
        maximumDuration = maxDuration
      } else if let maxDuration = maxDurationValue as? Int, maxDuration > 0 {
        maximumDuration = Double(maxDuration)
      } else if let maxDurationNumber = maxDurationValue as? NSNumber, maxDurationNumber.doubleValue > 0 {
        maximumDuration = maxDurationNumber.doubleValue
      }
    }
    
    if let minDurationValue = config["minDuration"] {
      if let minDuration = minDurationValue as? Double, minDuration > 0 {
        minimumDuration = minDuration
      } else if let minDuration = minDurationValue as? Int, minDuration > 0 {
        minimumDuration = Double(minDuration)
      } else if let minDurationNumber = minDurationValue as? NSNumber, minDurationNumber.doubleValue > 0 {
        minimumDuration = minDurationNumber.doubleValue
      }
    }
    
    cancelButtonText = config["cancelButtonText"] as? String ?? "Cancel"
    saveButtonText = config["saveButtonText"] as? String ?? "Save"
    jumpToPositionOnLoad = config["jumpToPositionOnLoad"] as? Double ?? 0
    enableHapticFeedback = config["enableHapticFeedback"] as? Bool ?? true
    zoomOnWaitingDuration = (config["zoomOnWaitingDuration"] as? Double ?? 5.0) / 1000.0 // convert ms to s
    autoplay = config["autoplay"] as? Bool ?? true
    headerText = config["headerText"] as? String
    headerTextSize = config["headerTextSize"] as? Int ?? 16
    headerTextColor = config["headerTextColor"] as? Double
    
    // Handle new color properties
    if let trimmerColorValue = config["trimmerColor"] as? Double {
        trimmerColor = RCTConvert.uiColor(trimmerColorValue) ?? UIColor.systemYellow
    }
    if let handleIconColorValue = config["handleIconColor"] as? Double {
        handleIconColor = RCTConvert.uiColor(handleIconColorValue) ?? UIColor.black
    }
  }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "status" {
            if player.status == .readyToPlay {
                loadingIndicator.stopAnimating()
                loadingIndicator.alpha = 0
                
                UIView.animate(withDuration: 0.25, animations: {
                    self.playBtn.alpha = 1
                    self.playBtn.isEnabled = true
                    self.saveBtn.alpha = 1
                    self.saveBtn.isEnabled = true
                })
                
                // Update save button corner radius for pill shape
                self.updateSaveButtonCornerRadius()
                
                if jumpToPositionOnLoad > 0 {
                    let duration = (asset?.duration.seconds ?? 0) * 1000
                    let time = jumpToPositionOnLoad > duration ? duration : jumpToPositionOnLoad
                    let cmtime = CMTime(value: CMTimeValue(time), timescale: 1000)
                    
                    self.seek(to: cmtime)
                    self.trimmer.progress = cmtime
                    self.currentTimeLabel.text = self.trimmer.selectedRange.duration.displayString
                }
                
                // Auto-play if enabled
                if self.autoplay {
                    if CMTimeCompare(self.trimmer.progress, self.trimmer.selectedRange.end) != -1 {
                        self.trimmer.progress = self.trimmer.selectedRange.start
                        self.seek(to: self.trimmer.progress)
                    }
                    self.player.play()
                    self.setPlayBtnIcon()
                }
            }
        }
    }
}

private extension UIButton {
    static func createButton(title: String? = nil, image: UIImage? = nil, font: UIFont? = nil, titleColor: UIColor? = nil, tintColor: UIColor? = nil, target: Any?, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        if let title = title {
            button.setTitle(title, for: .normal)
        }
        if let image = image {
            // Use original rendering mode to preserve colors and quality
            button.setImage(image.withRenderingMode(.alwaysOriginal), for: .normal)
            button.imageView?.contentMode = .scaleAspectFit
            button.imageView?.clipsToBounds = false
        }
        if let font = font {
            button.titleLabel?.font = font
        }
        if let titleColor = titleColor {
            button.setTitleColor(titleColor, for: .normal)
        }
        if let tintColor = tintColor {
            button.tintColor = tintColor
        } else if image != nil {
            // If no tint color specified and we have an image, use original rendering mode
            button.setImage(image?.withRenderingMode(.alwaysOriginal), for: .normal)
        }
        button.addTarget(target, action: action, for: .touchUpInside)
        return button
    }
}

private extension UIImage {
    func resize(to size: CGSize, scale: CGFloat? = nil) -> UIImage? {
        let targetScale = scale ?? self.scale
        UIGraphicsBeginImageContextWithOptions(size, false, targetScale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        return resizedImage?.withRenderingMode(.alwaysOriginal)
    }
}

private extension UILabel {
    static func createLabel(textAlignment: NSTextAlignment, textColor: UIColor) -> UILabel {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .caption1)
        label.textAlignment = textAlignment
        label.textColor = textColor
        return label
    }
}

