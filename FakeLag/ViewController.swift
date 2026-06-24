import UIKit
import NetworkExtension
import AVFoundation
import AudioToolbox

// MARK: - Shared app group config
private let kAppGroup   = "group.com.fakelag.app"
private let kLagKey     = "lagEnabled"
private let kDelayKey   = "lagDelayMs"
private let kTunnelBundle = "com.fakelag.app.tunnel"

class ViewController: UIViewController {

    // MARK: - UI Properties
    private var startButton: UIButton!
    private var statusLabel: UILabel!
    private var statusIndicator: UIView!
    private var timerLabel: UILabel!
    private var buttonSizeSlider: UISlider!
    private var sliderLabel: UILabel!
    private var subtitleLabel: UILabel!
    private var gradientLayer: CAGradientLayer!
    private var particleContainer: UIView!

    // MARK: - State
    private var isRunning = false
    private var countdownTimer: Timer?
    private var remainingSeconds = 0
    private var buttonSize: CGFloat = 180
    private var buttonWidthConstraint: NSLayoutConstraint!
    private var buttonHeightConstraint: NSLayoutConstraint!
    private var pulseAnimation: CAAnimationGroup?
    private var floatingWindow: FloatingButtonWindow?
    private var silenceEngine = AudioEngineSilence()
    private var isLagging = false

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupGradientBackground()
        setupParticles()
        setupUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = view.bounds
        startButton.layer.cornerRadius = startButton.bounds.width / 2
    }

    // MARK: - Background Setup
    private func setupGradientBackground() {
        gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor(red: 0.05, green: 0.05, blue: 0.15, alpha: 1).cgColor,
            UIColor(red: 0.08, green: 0.03, blue: 0.20, alpha: 1).cgColor,
            UIColor(red: 0.02, green: 0.08, blue: 0.18, alpha: 1).cgColor
        ]
        gradientLayer.locations = [0, 0.5, 1]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        gradientLayer.frame = view.bounds
        view.layer.insertSublayer(gradientLayer, at: 0)
    }

    private func setupParticles() {
        particleContainer = UIView(frame: view.bounds)
        particleContainer.isUserInteractionEnabled = false
        view.addSubview(particleContainer)

        for _ in 0..<20 {
            let dot = UIView()
            let size = CGFloat.random(in: 2...6)
            dot.frame = CGRect(x: CGFloat.random(in: 0...view.bounds.width),
                               y: CGFloat.random(in: 0...view.bounds.height),
                               width: size, height: size)
            dot.layer.cornerRadius = size / 2
            dot.backgroundColor = UIColor(red: 0.4, green: 0.6, blue: 1.0, alpha: CGFloat.random(in: 0.2...0.6))
            particleContainer.addSubview(dot)

            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = CGFloat.random(in: 0.1...0.5)
            anim.toValue = 0.0
            anim.duration = Double.random(in: 2.0...5.0)
            anim.repeatCount = .infinity
            anim.autoreverses = true
            anim.beginTime = CACurrentMediaTime() + Double.random(in: 0...3)
            dot.layer.add(anim, forKey: "pulse")
        }
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .clear

        // Title
        let titleLabel = UILabel()
        titleLabel.text = "FAKE LAG"
        titleLabel.font = UIFont.systemFont(ofSize: 36, weight: .black)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Subtitle
        subtitleLabel = UILabel()
        subtitleLabel.text = "Network Lag Simulator"
        subtitleLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        subtitleLabel.textColor = UIColor(red: 0.5, green: 0.7, blue: 1.0, alpha: 0.8)
        subtitleLabel.textAlignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Status Indicator Dot
        statusIndicator = UIView()
        statusIndicator.translatesAutoresizingMaskIntoConstraints = false
        statusIndicator.layer.cornerRadius = 6
        statusIndicator.backgroundColor = UIColor(red: 0.3, green: 0.9, blue: 0.5, alpha: 1)
        addGlowToView(statusIndicator, color: UIColor(red: 0.3, green: 0.9, blue: 0.5, alpha: 0.8))

        // Status Label
        statusLabel = UILabel()
        statusLabel.text = "STANDBY"
        statusLabel.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
        statusLabel.textColor = UIColor(red: 0.3, green: 0.9, blue: 0.5, alpha: 1)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        // Status stack
        let statusStack = UIStackView(arrangedSubviews: [statusIndicator, statusLabel])
        statusStack.axis = .horizontal
        statusStack.spacing = 8
        statusStack.alignment = .center
        statusStack.translatesAutoresizingMaskIntoConstraints = false

        // Timer Label
        timerLabel = UILabel()
        timerLabel.text = ""
        timerLabel.font = UIFont.monospacedSystemFont(ofSize: 18, weight: .bold)
        timerLabel.textColor = UIColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1)
        timerLabel.textAlignment = .center
        timerLabel.alpha = 0
        timerLabel.translatesAutoresizingMaskIntoConstraints = false

        // Main START Button
        startButton = createStartButton()

        // Slider label
        sliderLabel = UILabel()
        sliderLabel.text = "BUTTON SIZE: \(Int(buttonSize))pt"
        sliderLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        sliderLabel.textColor = UIColor(white: 1, alpha: 0.5)
        sliderLabel.textAlignment = .center
        sliderLabel.translatesAutoresizingMaskIntoConstraints = false

        // Slider
        buttonSizeSlider = UISlider()
        buttonSizeSlider.minimumValue = 80
        buttonSizeSlider.maximumValue = 280
        buttonSizeSlider.value = Float(buttonSize)
        buttonSizeSlider.tintColor = UIColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1)
        buttonSizeSlider.thumbTintColor = .white
        buttonSizeSlider.translatesAutoresizingMaskIntoConstraints = false
        buttonSizeSlider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)

        // Card view for controls
        let cardView = UIView()
        cardView.backgroundColor = UIColor(white: 1, alpha: 0.05)
        cardView.layer.cornerRadius = 20
        cardView.layer.borderWidth = 1
        cardView.layer.borderColor = UIColor(white: 1, alpha: 0.1).cgColor
        cardView.translatesAutoresizingMaskIntoConstraints = false

        // Add subviews
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(statusStack)
        view.addSubview(timerLabel)
        view.addSubview(startButton)
        view.addSubview(cardView)
        cardView.addSubview(sliderLabel)
        cardView.addSubview(buttonSizeSlider)

        // Constraints
        buttonWidthConstraint = startButton.widthAnchor.constraint(equalToConstant: buttonSize)
        buttonHeightConstraint = startButton.heightAnchor.constraint(equalToConstant: buttonSize)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            statusStack.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 20),
            statusStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            statusIndicator.widthAnchor.constraint(equalToConstant: 12),
            statusIndicator.heightAnchor.constraint(equalToConstant: 12),

            startButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            startButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            buttonWidthConstraint,
            buttonHeightConstraint,

            timerLabel.topAnchor.constraint(equalTo: startButton.bottomAnchor, constant: 24),
            timerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            cardView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),

            sliderLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            sliderLabel.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),

            buttonSizeSlider.topAnchor.constraint(equalTo: sliderLabel.bottomAnchor, constant: 12),
            buttonSizeSlider.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            buttonSizeSlider.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -20),
            buttonSizeSlider.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
        ])
    }

    private func createStartButton() -> UIButton {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("START", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 28, weight: .black)
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = buttonSize / 2
        button.clipsToBounds = false

        // Gradient fill
        let gradLayer = CAGradientLayer()
        gradLayer.colors = [
            UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1).cgColor,
            UIColor(red: 0.5, green: 0.2, blue: 1.0, alpha: 1).cgColor
        ]
        gradLayer.startPoint = CGPoint(x: 0, y: 0)
        gradLayer.endPoint = CGPoint(x: 1, y: 1)
        gradLayer.cornerRadius = buttonSize / 2
        gradLayer.frame = CGRect(x: 0, y: 0, width: buttonSize, height: buttonSize)
        button.layer.insertSublayer(gradLayer, at: 0)
        button.layer.name = "startButtonGrad"

        // Outer glow ring
        let glowRing = CALayer()
        glowRing.frame = CGRect(x: -8, y: -8, width: buttonSize + 16, height: buttonSize + 16)
        glowRing.cornerRadius = (buttonSize + 16) / 2
        glowRing.borderWidth = 2
        glowRing.borderColor = UIColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 0.5).cgColor
        glowRing.shadowColor = UIColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 1).cgColor
        glowRing.shadowRadius = 12
        glowRing.shadowOpacity = 0.8
        glowRing.shadowOffset = .zero
        button.layer.addSublayer(glowRing)
        button.layer.shadowColor = UIColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 1).cgColor
        button.layer.shadowRadius = 20
        button.layer.shadowOpacity = 0.6
        button.layer.shadowOffset = .zero

        button.addTarget(self, action: #selector(startButtonTapped), for: .touchUpInside)
        button.addTarget(self, action: #selector(buttonTouchDown), for: .touchDown)
        button.addTarget(self, action: #selector(buttonTouchUp), for: [.touchUpOutside, .touchCancel])
        return button
    }

    // MARK: - Actions

    @objc private func buttonTouchDown() {
        UIView.animate(withDuration: 0.1) {
            self.startButton.transform = CGAffineTransform(scaleX: 0.93, y: 0.93)
        }
    }

    @objc private func buttonTouchUp() {
        UIView.animate(withDuration: 0.1) {
            self.startButton.transform = .identity
        }
    }

    @objc private func startButtonTapped() {
        buttonTouchUp()
        
        if isRunning {
            // STOP active mode
            isRunning = false
            
            // Stop background audio session
            silenceEngine.stop()
            
            // Dismiss floating window
            DispatchQueue.main.async {
                self.floatingWindow?.isHidden = true
                self.floatingWindow = nil
            }
            
            // Make sure lag is disabled
            disableSystemLag()
            
            // Reset main app UI
            updateStatus(text: "STANDBY", color: UIColor(red: 0.3, green: 0.9, blue: 0.5, alpha: 1))
            startButton.setTitle("START", for: .normal)
            
            // Set startButton gradient back to normal
            if let gradLayer = startButton.layer.sublayers?.first(where: { $0.name == "startButtonGrad" }) as? CAGradientLayer {
                gradLayer.colors = [
                    UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1).cgColor,
                    UIColor(red: 0.5, green: 0.2, blue: 1.0, alpha: 1).cgColor
                ]
            }
        } else {
            // START mode
            isRunning = true
            
            // Start background silence to keep app alive
            silenceEngine.start()
            
            // Create and show the floating button
            DispatchQueue.main.async {
                let win = FloatingButtonWindow(actionHandler: { [weak self] in
                    self?.triggerLagCycleFromFloatingButton()
                })
                win.isHidden = false
                self.floatingWindow = win
            }
            
            // Visual feedback
            UIView.animate(withDuration: 0.15) {
                self.startButton.alpha = 0.7
            } completion: { _ in
                UIView.animate(withDuration: 0.15) {
                    self.startButton.alpha = 1
                }
            }

            // Haptic feedback
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            impact.impactOccurred()

            updateStatus(text: "FLOATING BUTTON ACTIVE", color: UIColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 1))
            startButton.setTitle("STOP", for: .normal)
            
            // Change startButton gradient to red/orange
            if let gradLayer = startButton.layer.sublayers?.first(where: { $0.name == "startButtonGrad" }) as? CAGradientLayer {
                gradLayer.colors = [
                    UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1).cgColor,
                    UIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1).cgColor
                ]
            }

            // Open Free Fire / Free Fire MAX
            openFreeFireGame()
        }
    }

    private func triggerLagCycleFromFloatingButton() {
        guard isRunning else { return }
        guard !isLagging else { return }
        enableSystemLag()
    }

    // MARK: - Free Fire launch

    private func openFreeFireGame() {
        let schemes = ["freefire://", "freefiremax://"]

        func tryNext(index: Int) {
            guard index < schemes.count else {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
                return
            }
            if let url = URL(string: schemes[index]) {
                UIApplication.shared.open(url, options: [:]) { success in
                    if !success { tryNext(index: index + 1) }
                }
            } else {
                tryNext(index: index + 1)
            }
        }

        tryNext(index: 0)
    }

    // MARK: - System-wide lag via NEVPNManager + Packet Tunnel

    private func enableSystemLag() {
        guard !isLagging else { return }
        isLagging = true
        
        if let floatWin = floatingWindow {
            floatWin.setLagActive(true)
        }

        // Signal the tunnel extension via shared UserDefaults (App Group)
        let defaults = UserDefaults(suiteName: kAppGroup)
        defaults?.set(true, forKey: kLagKey)
        defaults?.set(Date().timeIntervalSince1970, forKey: "lagStartTime")  // for smooth ramp
        defaults?.synchronize()

        // Load & start the VPN tunnel
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self = self else { return }
            let manager = managers?.first ?? NETunnelProviderManager()
            manager.localizedDescription = "FakeLag - Network Simulator"

            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = kTunnelBundle
            proto.serverAddress = "FakeLag"
            proto.providerConfiguration = [:]
            manager.protocolConfiguration = proto
            manager.isEnabled = true

            manager.saveToPreferences { saveError in
                if let e = saveError {
                    print("[FakeLag] VPN save error: \(e)")
                    return
                }
                manager.loadFromPreferences { _ in
                    do {
                        try (manager.connection as! NETunnelProviderSession).startTunnel(options: nil)
                        DispatchQueue.main.async {
                            self.onLagEnabled()
                            // Auto-disable after full 4-second ramp cycle
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                                self.disableSystemLag()
                            }
                        }
                    } catch {
                        print("[FakeLag] VPN start error: \(error)")
                        DispatchQueue.main.async {
                            LagURLProtocol.isLagEnabled = true
                            self.onLagEnabled()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                                self.disableSystemLag()
                            }
                        }
                    }
                }
            }
        }
    }

    private func disableSystemLag() {
        guard isLagging else { return }
        isLagging = false
        
        if let floatWin = floatingWindow {
            floatWin.setLagActive(false)
        }

        // Turn off lag flag in shared defaults
        let defaults = UserDefaults(suiteName: kAppGroup)
        defaults?.set(false, forKey: kLagKey)
        defaults?.synchronize()

        // Stop VPN tunnel
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            managers?.forEach { manager in
                manager.connection.stopVPNTunnel()
            }
        }

        // Also disable URLProtocol fallback
        LagURLProtocol.isLagEnabled = false

        DispatchQueue.main.async {
            self.onLagDisabled()
        }
    }

    private func onLagEnabled() {
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.warning)
        updateStatus(text: "⚡ LAG ACTIVE  0ms→600ms", color: UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1))
        startPulseAnimation()
        showTimer(seconds: 4)  // full 4-second spike cycle
        // Animate status label through lag phases
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.updateStatus(text: "⚡ PEAK LAG  600ms", color: UIColor(red: 1.0, green: 0.15, blue: 0.15, alpha: 1))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.updateStatus(text: "↓ LAG DROPPING  600ms→0ms", color: UIColor(red: 1.0, green: 0.5, blue: 0.1, alpha: 1))
        }
    }

    private func onLagDisabled() {
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        stopPulseAnimation()
        updateStatus(text: "STANDBY", color: UIColor(red: 0.3, green: 0.9, blue: 0.5, alpha: 1))
        hideTimer()
    }

    private func updateStatus(text: String, color: UIColor) {
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.3) {
                self.statusLabel.text = text
                self.statusLabel.textColor = color
                self.statusIndicator.backgroundColor = color
                self.addGlowToView(self.statusIndicator, color: color.withAlphaComponent(0.8))
            }
        }
    }

    private func showTimer(seconds: Int) {
        remainingSeconds = seconds
        timerLabel.text = "Stopping in \(remainingSeconds)s..."
        UIView.animate(withDuration: 0.3) { self.timerLabel.alpha = 1 }

        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            self.remainingSeconds -= 1
            if self.remainingSeconds <= 0 {
                timer.invalidate()
                self.hideTimer()
            } else {
                self.timerLabel.text = "Stopping in \(self.remainingSeconds)s..."
            }
        }
    }

    private func hideTimer() {
        countdownTimer?.invalidate()
        UIView.animate(withDuration: 0.3) { self.timerLabel.alpha = 0 }
    }

    private func startPulseAnimation() {
        let pulse1 = CABasicAnimation(keyPath: "transform.scale")
        pulse1.fromValue = 1.0
        pulse1.toValue = 1.08
        pulse1.duration = 0.5
        pulse1.autoreverses = true
        pulse1.repeatCount = .infinity
        startButton.layer.add(pulse1, forKey: "pulse")
    }

    private func stopPulseAnimation() {
        startButton.layer.removeAnimation(forKey: "pulse")
        startButton.transform = .identity
    }

    @objc private func sliderChanged(_ sender: UISlider) {
        buttonSize = CGFloat(sender.value)
        sliderLabel.text = "BUTTON SIZE: \(Int(buttonSize))pt"

        buttonWidthConstraint.constant = buttonSize
        buttonHeightConstraint.constant = buttonSize

        // Update gradient layer frame
        if let gradLayer = startButton.layer.sublayers?.first as? CAGradientLayer {
            gradLayer.frame = CGRect(x: 0, y: 0, width: buttonSize, height: buttonSize)
            gradLayer.cornerRadius = buttonSize / 2
        }

        UIView.animate(withDuration: 0.2) {
            self.view.layoutIfNeeded()
            self.startButton.layer.cornerRadius = self.buttonSize / 2
        }
    }

    // MARK: - Helpers
    private func addGlowToView(_ view: UIView, color: UIColor) {
        view.layer.shadowColor = color.cgColor
        view.layer.shadowRadius = 8
        view.layer.shadowOpacity = 1.0
        view.layer.shadowOffset = .zero
    }
}

// MARK: - Background Audio Silence Engine
class AudioEngineSilence {
    private let engine = AVAudioEngine()
    private var isPlaying = false
    
    func start() {
        guard !isPlaying else { return }
        isPlaying = true
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[FakeLag] Background audio session setup failed: \(error)")
        }
        
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let srcNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in abl {
                memset(buffer.mData, 0, Int(buffer.mDataByteSize))
            }
            return noErr
        }
        
        engine.attach(srcNode)
        engine.connect(srcNode, to: engine.mainMixerNode, format: format)
        engine.prepare()
        do {
            try engine.start()
            print("[FakeLag] Background audio engine started successfully.")
        } catch {
            print("[FakeLag] Background audio engine start failed: \(error)")
        }
    }
    
    func stop() {
        guard isPlaying else { return }
        isPlaying = false
        engine.stop()
        
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("[FakeLag] Audio session deactivation failed: \(error)")
        }
    }
}

// MARK: - Floating Button Window
class FloatingButtonWindow: UIWindow {
    
    init(actionHandler: @escaping () -> Void) {
        let initialFrame = CGRect(x: 100, y: 150, width: 80, height: 80)
        super.init(frame: initialFrame)
        setupWindow(actionHandler: actionHandler)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupWindow(actionHandler: @escaping () -> Void) {
        self.backgroundColor = .clear
        self.windowLevel = UIWindow.Level(rawValue: 1000000)
        self.clipsToBounds = false
        
        let vc = FloatingViewController()
        vc.actionHandler = actionHandler
        self.rootViewController = vc
    }
    
    func setLagActive(_ active: Bool) {
        guard let vc = rootViewController as? FloatingViewController else { return }
        vc.setLagActive(active)
    }
}

// MARK: - Floating View Controller
class FloatingViewController: UIViewController {
    var actionHandler: (() -> Void)?
    private var button: UIButton!
    private var timerLabel: UILabel!
    private var remainingSeconds = 0
    private var countdownTimer: Timer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        
        // Main round button
        button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("LAG", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .black)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(red: 0.1, green: 0.6, blue: 1.0, alpha: 0.85) // Standby Blue
        button.layer.cornerRadius = 35 // 70x70 size
        button.layer.borderWidth = 2.5
        button.layer.borderColor = UIColor.white.cgColor
        
        // Shadow/glow effect
        button.layer.shadowColor = UIColor(red: 0.1, green: 0.6, blue: 1.0, alpha: 1).cgColor
        button.layer.shadowOffset = .zero
        button.layer.shadowRadius = 12
        button.layer.shadowOpacity = 0.8
        
        view.addSubview(button)
        
        // Countdown timer label on top of button
        timerLabel = UILabel()
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        timerLabel.text = ""
        timerLabel.font = UIFont.monospacedSystemFont(ofSize: 18, weight: .black)
        timerLabel.textColor = .white
        timerLabel.textAlignment = .center
        timerLabel.alpha = 0
        view.addSubview(timerLabel)
        
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.topAnchor, constant: 5),
            button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 5),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -5),
            button.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -5),
            
            timerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            timerLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        
        button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        
        // Pan gesture
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        view.addGestureRecognizer(panGesture)
    }
    
    @objc private func buttonTapped() {
        actionHandler?()
    }
    
    func setLagActive(_ active: Bool) {
        countdownTimer?.invalidate()
        if active {
            remainingSeconds = 4
            timerLabel.text = "\(remainingSeconds)"
            
            UIView.animate(withDuration: 0.2) {
                self.button.backgroundColor = UIColor(red: 1.0, green: 0.25, blue: 0.25, alpha: 0.95) // Active Red
                self.button.layer.borderColor = UIColor(red: 1.0, green: 0.6, blue: 0.6, alpha: 1).cgColor
                self.button.layer.shadowColor = UIColor.red.cgColor
                self.button.setTitle("", for: .normal)
                self.timerLabel.alpha = 1
            }
            
            // Add pulse animation
            let anim = CABasicAnimation(keyPath: "transform.scale")
            anim.fromValue = 1.0
            anim.toValue = 1.15
            anim.duration = 0.4
            anim.autoreverses = true
            anim.repeatCount = .infinity
            button.layer.add(anim, forKey: "pulse")
            
            countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                guard let self = self else { return }
                self.remainingSeconds -= 1
                if self.remainingSeconds <= 0 {
                    timer.invalidate()
                } else {
                    self.timerLabel.text = "\(self.remainingSeconds)"
                }
            }
        } else {
            button.layer.removeAnimation(forKey: "pulse")
            UIView.animate(withDuration: 0.2) {
                self.button.backgroundColor = UIColor(red: 0.1, green: 0.6, blue: 1.0, alpha: 0.85) // Standby Blue
                self.button.layer.borderColor = UIColor.white.cgColor
                self.button.layer.shadowColor = UIColor(red: 0.1, green: 0.6, blue: 1.0, alpha: 1).cgColor
                self.button.setTitle("LAG", for: .normal)
                self.timerLabel.alpha = 0
            }
        }
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let window = view.window else { return }
        let translation = gesture.translation(in: view)
        
        let newCenter = CGPoint(
            x: window.center.x + translation.x,
            y: window.center.y + translation.y
        )
        
        let screenBounds = UIScreen.main.bounds
        let halfWidth = window.bounds.width / 2
        let halfHeight = window.bounds.height / 2
        
        window.center = CGPoint(
            x: min(max(newCenter.x, halfWidth), screenBounds.width - halfWidth),
            y: min(max(newCenter.y, halfHeight), screenBounds.height - halfHeight)
        )
        
        gesture.setTranslation(.zero, in: view)
    }
}
