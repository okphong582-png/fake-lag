import UIKit
import NetworkExtension

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
        guard !isRunning else { return }
        isRunning = true

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

        updateStatus(text: "SWITCHING APP...", color: UIColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 1))

        // Open Free Fire / Free Fire MAX
        openFreeFireGame()

        // After 2 seconds: start the VPN tunnel and enable lag
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.enableSystemLag()

            // After another 2 seconds: stop lag
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.disableSystemLag()
            }
        }
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
        // Signal the tunnel extension via shared UserDefaults (App Group)
        let defaults = UserDefaults(suiteName: kAppGroup)
        defaults?.set(true, forKey: kLagKey)
        defaults?.set(800, forKey: kDelayKey)
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
                        }
                    } catch {
                        print("[FakeLag] VPN start error: \(error)")
                        DispatchQueue.main.async {
                            // Fallback to URLProtocol-based lag if tunnel fails
                            LagURLProtocol.isLagEnabled = true
                            self.onLagEnabled()
                        }
                    }
                }
            }
        }
    }

    private func disableSystemLag() {
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
        updateStatus(text: "⚡ LAG ACTIVE", color: UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1))
        startPulseAnimation()
        showTimer(seconds: 2)
    }

    private func onLagDisabled() {
        isRunning = false
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
