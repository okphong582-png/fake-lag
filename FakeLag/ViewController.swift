import UIKit
import NetworkExtension
import AVFoundation
import AudioToolbox

// MARK: - Shared Configuration
private let kAppGroup     = "group.com.fakelag.app"
private let kLagKey       = "lagEnabled"
private let kTunnelBundle = "com.fakelag.app.tunnel"
private let kSavedKeyName = "licenseKey"

class ViewController: UIViewController {

    // MARK: - Main UI Elements
    private var actionLabel: UILabel!
    private var statusLabel: UILabel!
    private var statusIndicator: UIView!
    private var expiryLabel: UILabel!
    private var gradientLayer: CAGradientLayer!
    private var particleContainer: UIView!
    private var glowContainer: UIView!

    // MARK: - Activation Overlay Elements
    private var activationOverlay: UIVisualEffectView?
    private var keyTextField: UITextField?
    private var overlayErrorLabel: UILabel?
    private var overlaySpinner: UIActivityIndicatorView?
    private var overlayActivateButton: UIButton?

    // MARK: - State Properties
    private var isRunning = false
    private var isLagging = false
    private var floatingWindow: FloatingButtonWindow?
    private var silenceEngine = AudioEngineSilence()
    private var antiCrackTimer: Timer?
    private var isCheckingKey = false

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupPremiumBackground()
        setupParticles()
        setupMainUI()
        
        // Check for stored key on start
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.checkStoredKey()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = view.bounds
    }

    // MARK: - Premium Styling & Background
    private func setupPremiumBackground() {
        view.backgroundColor = UIColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0)

        // Subtle dark ambient gradient
        gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1.0).cgColor,
            UIColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0).cgColor,
            UIColor(red: 0.01, green: 0.01, blue: 0.02, alpha: 1.0).cgColor
        ]
        gradientLayer.locations = [0, 0.5, 1]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        gradientLayer.frame = view.bounds
        view.layer.insertSublayer(gradientLayer, at: 0)

        // Accent glow circles in background
        glowContainer = UIView(frame: view.bounds)
        glowContainer.isUserInteractionEnabled = false
        view.insertSubview(glowContainer, at: 1)

        let colors = [
            UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.12).cgColor,
            UIColor(red: 0.5, green: 0.0, blue: 1.0, alpha: 0.08).cgColor
        ]
        let frames = [
            CGRect(x: -100, y: 100, width: 350, height: 350),
            CGRect(x: view.bounds.width - 250, y: view.bounds.height - 350, width: 350, height: 350)
        ]

        for i in 0..<2 {
            let glow = UIView(frame: frames[i])
            glow.layer.cornerRadius = frames[i].width / 2
            let rad = CAGradientLayer()
            rad.type = .radial
            rad.colors = [colors[i], UIColor.clear.cgColor]
            rad.startPoint = CGPoint(x: 0.5, y: 0.5)
            rad.endPoint = CGPoint(x: 1, y: 1)
            rad.frame = glow.bounds
            glow.layer.addSublayer(rad)
            glowContainer.addSubview(glow)
        }
    }

    private func setupParticles() {
        particleContainer = UIView(frame: view.bounds)
        particleContainer.isUserInteractionEnabled = false
        view.insertSubview(particleContainer, at: 2)

        for _ in 0..<18 {
            let dot = UIView()
            let size = CGFloat.random(in: 2...4)
            dot.frame = CGRect(x: CGFloat.random(in: 0...view.bounds.width),
                               y: CGFloat.random(in: 0...view.bounds.height),
                               width: size, height: size)
            dot.layer.cornerRadius = size / 2
            dot.backgroundColor = UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: CGFloat.random(in: 0.15...0.4))
            particleContainer.addSubview(dot)

            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = CGFloat.random(in: 0.1...0.3)
            anim.toValue = 0.0
            anim.duration = Double.random(in: 3.0...6.0)
            anim.repeatCount = .infinity
            anim.autoreverses = true
            anim.beginTime = CACurrentMediaTime() + Double.random(in: 0...3)
            dot.layer.add(anim, forKey: "pulse")
        }
    }

    // MARK: - Main UI Layout
    private func setupMainUI() {
        // App Title
        let titleLabel = UILabel()
        titleLabel.text = "FAKELAG"
        titleLabel.font = UIFont.systemFont(ofSize: 32, weight: .black)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addGlowToLayer(titleLabel.layer, color: UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.5).cgColor, radius: 10)

        // Status Indicator Row
        statusIndicator = UIView()
        statusIndicator.translatesAutoresizingMaskIntoConstraints = false
        statusIndicator.layer.cornerRadius = 5
        statusIndicator.backgroundColor = UIColor(white: 1.0, alpha: 0.4)

        statusLabel = UILabel()
        statusLabel.text = "SYSTEM STANDBY"
        statusLabel.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        statusLabel.textColor = UIColor(white: 1.0, alpha: 0.5)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let statusStack = UIStackView(arrangedSubviews: [statusIndicator, statusLabel])
        statusStack.axis = .horizontal
        statusStack.spacing = 8
        statusStack.alignment = .center
        statusStack.translatesAutoresizingMaskIntoConstraints = false

        // Tapable Action Label (Start/Stop System)
        actionLabel = UILabel()
        actionLabel.text = "TAP TO START"
        actionLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        actionLabel.textColor = .white
        actionLabel.textAlignment = .center
        actionLabel.isUserInteractionEnabled = true
        actionLabel.translatesAutoresizingMaskIntoConstraints = false
        actionLabel.layer.borderWidth = 1.5
        actionLabel.layer.borderColor = UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.4).cgColor
        actionLabel.layer.cornerRadius = 60
        actionLabel.clipsToBounds = true
        actionLabel.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 0.6)
        addGlowToLayer(actionLabel.layer, color: UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.3).cgColor, radius: 15)

        let tap = UITapGestureRecognizer(target: self, action: #selector(actionLabelTapped))
        actionLabel.addGestureRecognizer(tap)

        // Key info display (bottom)
        expiryLabel = UILabel()
        expiryLabel.text = "Verifying license key..."
        expiryLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        expiryLabel.textColor = UIColor(white: 1.0, alpha: 0.4)
        expiryLabel.textAlignment = .center
        expiryLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleLabel)
        view.addSubview(statusStack)
        view.addSubview(actionLabel)
        view.addSubview(expiryLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 50),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            statusStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            statusStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusIndicator.widthAnchor.constraint(equalToConstant: 10),
            statusIndicator.heightAnchor.constraint(equalToConstant: 10),

            actionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            actionLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            actionLabel.widthAnchor.constraint(equalToConstant: 220),
            actionLabel.heightAnchor.constraint(equalToConstant: 120),

            expiryLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            expiryLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])

        startPulseAnimation()
    }

    // MARK: - License Verification Logic
    private func checkStoredKey() {
        guard !isCheckingKey else { return }
        isCheckingKey = true

        if let savedKey = UserDefaults.standard.string(forKey: kSavedKeyName) {
            validateLicenseKey(key: savedKey) { [weak self] success, details in
                self?.isCheckingKey = false
                DispatchQueue.main.async {
                    if success {
                        self?.expiryLabel.text = "License Expiry: \(details)"
                        self?.startAntiCrackDaemon()
                    } else {
                        self?.showActivationOverlay(errorMessage: details)
                    }
                }
            }
        } else {
            isCheckingKey = false
            showActivationOverlay(errorMessage: nil)
        }
    }

    private func validateLicenseKey(key: String, completion: @escaping (Bool, String) -> Void) {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let url = URL(string: "https://appchatai-313e3-default-rtdb.firebaseio.com/keys/\(cleanKey).json") else {
            completion(false, "Invalid License Endpoint")
            return
        }

        fetchPublicIP { [weak self] currentIP in
            guard let self = self else {
                completion(false, "Internal Error")
                return
            }
            guard let currentIP = currentIP else {
                completion(false, "No internet connection detected")
                return
            }

            URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
                guard let self = self else { return }
                
                if let error = error {
                    completion(false, "Connection error: \(error.localizedDescription)")
                    return
                }

                guard let data = data else {
                    completion(false, "No database response")
                    return
                }

                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let isRevoked = json["isRevoked"] as? Bool ?? false
                        let expiryTime = json["expiryTime"] as? Int ?? 0
                        let boundIP = json["ip"] as? String ?? ""

                        if isRevoked {
                            completion(false, "License key has been revoked")
                            return
                        }

                        let nowSeconds = Int(Date().timeIntervalSince1970)
                        if expiryTime != -1 && nowSeconds > expiryTime {
                            completion(false, "License key has expired")
                            return
                        }

                        // IP Lock validation
                        if boundIP.isEmpty {
                            // First time use, auto-bind
                            self.bindIPToKey(key: cleanKey, ip: currentIP) { success in
                                if success {
                                    let expiryStr = expiryTime == -1 ? "Lifetime (Vĩnh viễn)" : self.formatTimestamp(expiryTime)
                                    completion(true, expiryStr)
                                } else {
                                    completion(false, "Failed to lock IP Address")
                                }
                            }
                        } else if boundIP != currentIP {
                            completion(false, "Key bound to another IP: \(boundIP)")
                        } else {
                            let expiryStr = expiryTime == -1 ? "Lifetime (Vĩnh viễn)" : self.formatTimestamp(expiryTime)
                            completion(true, expiryStr)
                        }
                    } else {
                        completion(false, "Invalid/Nonexistent License Key")
                    }
                } catch {
                    completion(false, "Activation response parse error")
                }
            }.resume()
        }
    }

    private func bindIPToKey(key: String, ip: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "https://appchatai-313e3-default-rtdb.firebaseio.com/keys/\(key).json") else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let patchData = ["ip": ip]
        request.httpBody = try? JSONSerialization.data(withJSONObject: patchData)

        URLSession.shared.dataTask(with: request) { data, _, error in
            completion(error == nil && data != nil)
        }.resume()
    }

    private func fetchPublicIP(completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://api.ipify.org?format=json") else {
            completion(nil)
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ip = json["ip"] as? String else {
                completion(nil)
                return
            }
            completion(ip)
        }.resume()
    }

    private func formatTimestamp(_ stamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(stamp))
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd HH:mm"
        return format.string(from: date)
    }

    // MARK: - Background Anti-Crack Daemon
    private func startAntiCrackDaemon() {
        antiCrackTimer?.invalidate()
        antiCrackTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            guard let self = self, let savedKey = UserDefaults.standard.string(forKey: kSavedKeyName) else { return }
            self.validateLicenseKey(key: savedKey) { isValid, details in
                if !isValid {
                    self.handleActivationFailure(reason: details)
                } else {
                    DispatchQueue.main.async {
                        self.expiryLabel.text = "License Expiry: \(details)"
                    }
                }
            }
        }
    }

    private func stopAntiCrackDaemon() {
        antiCrackTimer?.invalidate()
        antiCrackTimer = nil
    }

    private func handleActivationFailure(reason: String) {
        stopAntiCrackDaemon()
        
        // Terminate any running lag services instantly
        isRunning = false
        isLagging = false
        disableSystemLag()
        silenceEngine.stop()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.floatingWindow?.isHidden = true
            self.floatingWindow = nil

            UserDefaults.standard.removeObject(forKey: kSavedKeyName)
            self.showActivationOverlay(errorMessage: reason)
        }
    }

    // MARK: - Activation View Overlay UI
    private func showActivationOverlay(errorMessage: String?) {
        if activationOverlay != nil {
            overlayErrorLabel?.text = errorMessage
            overlayErrorLabel?.isHidden = errorMessage == nil
            overlaySpinner?.stopAnimating()
            overlayActivateButton?.isHidden = false
            return
        }

        let blur = UIBlurEffect(style: .dark)
        let visualEffectView = UIVisualEffectView(effect: blur)
        visualEffectView.frame = view.bounds
        visualEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(visualEffectView)
        activationOverlay = visualEffectView

        // Centered Card Container
        let card = UIView()
        card.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 0.8)
        card.layer.cornerRadius = 24
        card.layer.borderWidth = 1.0
        card.layer.borderColor = UIColor(white: 1.0, alpha: 0.08).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.contentView.addSubview(card)

        // Card elements
        let icon = UIImageView(image: UIImage(systemName: "lock.shield"))
        icon.tintColor = UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1.0)
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = "KEY REQUIRED"
        title.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        title.textColor = .white
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        let textfieldWrapper = UIView()
        textfieldWrapper.backgroundColor = UIColor(white: 1.0, alpha: 0.03)
        textfieldWrapper.layer.cornerRadius = 12
        textfieldWrapper.layer.borderWidth = 1.0
        textfieldWrapper.layer.borderColor = UIColor(white: 1.0, alpha: 0.1).cgColor
        textfieldWrapper.translatesAutoresizingMaskIntoConstraints = false

        let field = UITextField()
        field.placeholder = "Enter license activation key"
        field.textColor = .white
        field.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .bold)
        field.textAlignment = .center
        field.keyboardAppearance = .dark
        field.autocorrectionType = .no
        field.autocapitalizationType = .allCharacters
        field.translatesAutoresizingMaskIntoConstraints = false
        keyTextField = field

        textfieldWrapper.addSubview(field)

        let errLabel = UILabel()
        errLabel.text = errorMessage
        errLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        errLabel.textColor = UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
        errLabel.textAlignment = .center
        errLabel.numberOfLines = 2
        errLabel.translatesAutoresizingMaskIntoConstraints = false
        errLabel.isHidden = errorMessage == nil
        overlayErrorLabel = errLabel

        let btnActivate = UIButton(type: .custom)
        btnActivate.setTitle("ACTIVATE", for: .normal)
        btnActivate.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .bold)
        btnActivate.setTitleColor(.black, for: .normal)
        btnActivate.backgroundColor = UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1.0)
        btnActivate.layer.cornerRadius = 12
        btnActivate.translatesAutoresizingMaskIntoConstraints = false
        btnActivate.addTarget(self, action: #selector(overlayActivateTapped), for: .touchUpInside)
        overlayActivateButton = btnActivate

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        overlaySpinner = spinner

        let btnBuyKey = UIButton(type: .system)
        btnBuyKey.setTitle("Buy Premium Key (Zalo)", for: .normal)
        btnBuyKey.setTitleColor(UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1.0), for: .normal)
        btnBuyKey.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        btnBuyKey.translatesAutoresizingMaskIntoConstraints = false
        btnBuyKey.addTarget(self, action: #selector(buyKeyTapped), for: .touchUpInside)

        card.addSubview(icon)
        card.addSubview(title)
        card.addSubview(textfieldWrapper)
        card.addSubview(errLabel)
        card.addSubview(btnActivate)
        card.addSubview(spinner)
        card.addSubview(btnBuyKey)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: visualEffectView.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: visualEffectView.centerYAnchor, constant: -20),
            card.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 40),
            card.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -40),

            icon.topAnchor.constraint(equalTo: card.topAnchor, constant: 28),
            icon.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 50),
            icon.heightAnchor.constraint(equalToConstant: 50),

            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 14),
            title.centerXAnchor.constraint(equalTo: card.centerXAnchor),

            textfieldWrapper.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 24),
            textfieldWrapper.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            textfieldWrapper.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            textfieldWrapper.heightAnchor.constraint(equalToConstant: 50),

            field.leadingAnchor.constraint(equalTo: textfieldWrapper.leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: textfieldWrapper.trailingAnchor, constant: -10),
            field.centerYAnchor.constraint(equalTo: textfieldWrapper.centerYAnchor),

            errLabel.topAnchor.constraint(equalTo: textfieldWrapper.bottomAnchor, constant: 12),
            errLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            errLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

            btnActivate.topAnchor.constraint(equalTo: errLabel.bottomAnchor, constant: 16),
            btnActivate.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            btnActivate.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            btnActivate.heightAnchor.constraint(equalToConstant: 50),

            spinner.centerXAnchor.constraint(equalTo: btnActivate.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: btnActivate.centerYAnchor),

            btnBuyKey.topAnchor.constraint(equalTo: btnActivate.bottomAnchor, constant: 18),
            btnBuyKey.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            btnBuyKey.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24)
        ])

        visualEffectView.alpha = 0.0
        UIView.animate(withDuration: 0.3) {
            visualEffectView.alpha = 1.0
        }
    }

    @objc private func overlayActivateTapped() {
        guard let key = keyTextField?.text?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), !key.isEmpty else {
            overlayErrorLabel?.text = "Key cannot be empty"
            overlayErrorLabel?.isHidden = false
            return
        }

        overlayErrorLabel?.isHidden = true
        overlayActivateButton?.isHidden = true
        overlaySpinner?.startAnimating()

        validateLicenseKey(key: key) { [weak self] success, details in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.overlaySpinner?.stopAnimating()
                self.overlayActivateButton?.isHidden = false

                if success {
                    UserDefaults.standard.set(key, forKey: kSavedKeyName)
                    self.expiryLabel.text = "License Expiry: \(details)"
                    self.startAntiCrackDaemon()
                    
                    UIView.animate(withDuration: 0.3, animations: {
                        self.activationOverlay?.alpha = 0.0
                    }) { _ in
                        self.activationOverlay?.removeFromSuperview()
                        self.activationOverlay = nil
                    }
                } else {
                    self.overlayErrorLabel?.text = details
                    self.overlayErrorLabel?.isHidden = false
                }
            }
        }
    }

    @objc private func buyKeyTapped() {
        if let url = URL(string: "https://zalo.me/0866445455") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    // MARK: - Action Triggers
    @objc private func actionLabelTapped() {
        // Impact feedback
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()

        if isRunning {
            isRunning = false
            silenceEngine.stop()

            DispatchQueue.main.async { [weak self] in
                self?.floatingWindow?.isHidden = true
                self?.floatingWindow = nil
            }

            disableSystemLag()
            actionLabel.text = "TAP TO START"
            updateStatus(text: "SYSTEM STANDBY", color: UIColor(white: 1.0, alpha: 0.4))
            
            UIView.animate(withDuration: 0.3) {
                self.actionLabel.layer.borderColor = UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.4).cgColor
                self.addGlowToLayer(self.actionLabel.layer, color: UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.3).cgColor, radius: 15)
            }
        } else {
            isRunning = true
            silenceEngine.start()

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let win = FloatingButtonWindow(actionHandler: { [weak self] in
                    self?.triggerLagCycleFromFloatingButton()
                })
                win.isHidden = false
                self.floatingWindow = win
            }

            actionLabel.text = "TAP TO STOP"
            updateStatus(text: "SERVICE RUNNING", color: UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1.0))

            UIView.animate(withDuration: 0.3) {
                self.actionLabel.layer.borderColor = UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 0.8).cgColor
                self.addGlowToLayer(self.actionLabel.layer, color: UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 0.5).cgColor, radius: 15)
            }
        }
    }

    private func triggerLagCycleFromFloatingButton() {
        guard isRunning else { return }
        if isLagging {
            disableSystemLag()
        } else {
            enableSystemLag()
        }
    }

    // MARK: - Lag Tunnel Activation Controls
    private func enableSystemLag() {
        guard !isLagging else { return }
        isLagging = true

        floatingWindow?.setLagActive(true)

        // Write lag flag to App Group Defaults
        let defaults = UserDefaults(suiteName: kAppGroup)
        defaults?.set(true, forKey: kLagKey)
        defaults?.synchronize()

        // Start VPN Tunnel Configuration
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self = self else { return }
            let manager = managers?.first ?? NETunnelProviderManager()
            manager.localizedDescription = "FakeLag Tunnel"

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
                            LagURLProtocol.isLagEnabled = true
                            self.onLagEnabled()
                        }
                    }
                }
            }
        }
    }

    private func disableSystemLag() {
        guard isLagging else { return }
        isLagging = false

        floatingWindow?.setLagActive(false)

        let defaults = UserDefaults(suiteName: kAppGroup)
        defaults?.set(false, forKey: kLagKey)
        defaults?.synchronize()

        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            managers?.forEach { manager in
                manager.connection.stopVPNTunnel()
            }
        }

        LagURLProtocol.isLagEnabled = false

        DispatchQueue.main.async { [weak self] in
            self?.onLagDisabled()
        }
    }

    private func onLagEnabled() {
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.warning)
        updateStatus(text: "LAG SYSTEM ACTIVE (400ms)", color: UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0))
        startStatusPulse()
    }

    private func onLagDisabled() {
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        stopStatusPulse()
        if isRunning {
            updateStatus(text: "SERVICE RUNNING", color: UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1.0))
        } else {
            updateStatus(text: "SYSTEM STANDBY", color: UIColor(white: 1.0, alpha: 0.4))
        }
    }

    private func updateStatus(text: String, color: UIColor) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            UIView.transition(with: self.statusLabel, duration: 0.2, options: .transitionCrossDissolve) {
                self.statusLabel.text = text
                self.statusLabel.textColor = color
            }
            UIView.animate(withDuration: 0.2) {
                self.statusIndicator.backgroundColor = color
                self.addGlowToLayer(self.statusIndicator.layer, color: color.cgColor, radius: 8)
            }
        }
    }

    // MARK: - UI Animations & Helpers
    private func startPulseAnimation() {
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.0
        pulse.toValue = 1.04
        pulse.duration = 1.0
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        actionLabel.layer.add(pulse, forKey: "pulse")
    }

    private func startStatusPulse() {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.4
        pulse.duration = 0.4
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        statusLabel.layer.add(pulse, forKey: "statusPulse")
    }

    private func stopStatusPulse() {
        statusLabel.layer.removeAnimation(forKey: "statusPulse")
        statusLabel.alpha = 1.0
    }

    private func addGlowToLayer(_ layer: CALayer, color: CGColor, radius: CGFloat) {
        layer.shadowColor = color
        layer.shadowRadius = radius
        layer.shadowOpacity = 1.0
        layer.shadowOffset = .zero
    }
}

// MARK: - Background Audio Engine
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
            print("[FakeLag] Silence Audio category config failed: \(error)")
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
        } catch {
            print("[FakeLag] Silence Audio start failed: \(error)")
        }
    }
    
    func stop() {
        guard isPlaying else { return }
        isPlaying = false
        engine.stop()
        
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("[FakeLag] Silence Audio deactivate failed: \(error)")
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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        
        // Circular button
        button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("OFF", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .black)
        button.setTitleColor(.white, for: .normal)
        
        // Matte dark obsidian look
        button.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 0.85)
        button.layer.cornerRadius = 35 // 70x70 size
        button.layer.borderWidth = 2.0
        button.layer.borderColor = UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.8).cgColor
        
        // Deep blue outer glow
        button.layer.shadowColor = UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.8).cgColor
        button.layer.shadowOffset = .zero
        button.layer.shadowRadius = 10
        button.layer.shadowOpacity = 0.8
        
        view.addSubview(button)
        
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.topAnchor, constant: 5),
            button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 5),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -5),
            button.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -5)
        ])
        
        button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        
        // Dynamic Pan gesture
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        view.addGestureRecognizer(panGesture)
    }
    
    @objc private func buttonTapped() {
        actionHandler?()
    }
    
    func setLagActive(_ active: Bool) {
        if active {
            UIView.animate(withDuration: 0.2) { [weak self] in
                guard let self = self else { return }
                self.button.backgroundColor = UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 0.95)
                self.button.layer.borderColor = UIColor(red: 1.0, green: 0.5, blue: 0.5, alpha: 1.0).cgColor
                self.button.layer.shadowColor = UIColor.red.cgColor
                self.button.setTitle("ON", for: .normal)
            }
            
            // Add pulse animation
            let anim = CABasicAnimation(keyPath: "transform.scale")
            anim.fromValue = 1.0
            anim.toValue = 1.15
            anim.duration = 0.4
            anim.autoreverses = true
            anim.repeatCount = .infinity
            button.layer.add(anim, forKey: "pulse")
        } else {
            button.layer.removeAnimation(forKey: "pulse")
            UIView.animate(withDuration: 0.2) { [weak self] in
                guard let self = self else { return }
                self.button.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 0.85)
                self.button.layer.borderColor = UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.8).cgColor
                self.button.layer.shadowColor = UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.8).cgColor
                self.button.setTitle("OFF", for: .normal)
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
