import UIKit
import NetworkExtension
import AVFoundation
import AudioToolbox
import AVKit
import ImageIO

// MARK: - Shared Configuration
private var kAppGroup: String {
    if let mainID = Bundle.main.bundleIdentifier {
        return "group.\(mainID)"
    }
    return "group.com.fakelag.app"
}
private let kLagKey       = "lagEnabled"
private var kTunnelBundle: String {
    if let mainID = Bundle.main.bundleIdentifier {
        return "\(mainID).tunnel"
    }
    return "com.fakelag.app.tunnel"
}
private let kSavedKeyName = "licenseKey"

// MARK: - PiP Manager Protocol (iOS 14+ safe interface)
protocol PiPManagerProtocol: AnyObject {
    func start()
    func stop()
    func setLagActive(_ active: Bool)
}

class ViewController: UIViewController {

    // MARK: - Main UI Elements
    private var backgroundImageView: UIImageView!
    private var actionLabel: UILabel!
    private var statusLabel: UILabel!
    private var statusIndicator: UIView!
    private var expiryLabel: UILabel!
    private var modeSegmentedControl: UISegmentedControl!
    var playerContainerView: UIView!

    // MARK: - Activation Overlay Elements
    private var activationOverlay: UIVisualEffectView?
    private var keyTextField: UITextField?
    private var overlayErrorLabel: UILabel?
    private var overlaySpinner: UIActivityIndicatorView?
    private var overlayActivateButton: UIButton?

    // MARK: - State Properties
    var isRunning = false
    private var isLagging = false
    private var floatingWindow: FloatingButtonWindow?
    private var silenceEngine = AudioEngineSilence()
    private var antiCrackTimer: Timer?
    private var isCheckingKey = false

    // MARK: - Protocol-based PiP Manager
    private var pipManager: PiPManagerProtocol?

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupGifBackground()
        setupMainUI()
        
        // Check for stored key on start
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.checkStoredKey()
        }
    }

    // MARK: - Loop GIF Background
    private func setupGifBackground() {
        backgroundImageView = UIImageView()
        backgroundImageView.contentMode = .scaleAspectFill
        backgroundImageView.translatesAutoresizingMaskIntoConstraints = false
        
        if let gifImage = UIImage.gifImageWithName("3987") {
            backgroundImageView.image = gifImage
        } else {
            print("[FakeLag] Warning: 3987.gif could not be loaded")
        }
        
        view.addSubview(backgroundImageView)
        
        NSLayoutConstraint.activate([
            backgroundImageView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backgroundImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
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
        addGlowToLayer(titleLabel.layer, color: UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.8).cgColor, radius: 10)

        // Mode Segmented Control (TrollStore vs Esign PiP)
        modeSegmentedControl = UISegmentedControl(items: ["TrollStore Mode", "Esign Mode (PiP)"])
        modeSegmentedControl.selectedSegmentIndex = 0
        modeSegmentedControl.backgroundColor = UIColor(white: 0.0, alpha: 0.6)
        modeSegmentedControl.selectedSegmentTintColor = UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.8)
        
        let normalAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 12, weight: .bold)]
        let selectedAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.black, .font: UIFont.systemFont(ofSize: 12, weight: .bold)]
        
        modeSegmentedControl.setTitleTextAttributes(normalAttributes, for: .normal)
        modeSegmentedControl.setTitleTextAttributes(selectedAttributes, for: .selected)
        modeSegmentedControl.translatesAutoresizingMaskIntoConstraints = false

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

        // Pure borderless text action label (Tap to Start)
        actionLabel = UILabel()
        actionLabel.text = "TAP TO START"
        actionLabel.font = UIFont.systemFont(ofSize: 28, weight: .black)
        actionLabel.textColor = .white
        actionLabel.textAlignment = .center
        actionLabel.isUserInteractionEnabled = true
        actionLabel.translatesAutoresizingMaskIntoConstraints = false
        addGlowToLayer(actionLabel.layer, color: UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.8).cgColor, radius: 15)

        let tap = UITapGestureRecognizer(target: self, action: #selector(actionLabelTapped))
        actionLabel.addGestureRecognizer(tap)

        // Key info display (bottom)
        expiryLabel = UILabel()
        expiryLabel.text = "Verifying license key..."
        expiryLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        expiryLabel.textColor = UIColor(white: 1.0, alpha: 0.5)
        expiryLabel.textAlignment = .center
        expiryLabel.translatesAutoresizingMaskIntoConstraints = false

        playerContainerView = UIView()
        playerContainerView.translatesAutoresizingMaskIntoConstraints = false
        playerContainerView.alpha = 0.01

        view.addSubview(titleLabel)
        view.addSubview(modeSegmentedControl)
        view.addSubview(statusStack)
        view.addSubview(actionLabel)
        view.addSubview(expiryLabel)
        view.addSubview(playerContainerView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            modeSegmentedControl.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            modeSegmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            modeSegmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            modeSegmentedControl.heightAnchor.constraint(equalToConstant: 36),

            statusStack.topAnchor.constraint(equalTo: modeSegmentedControl.bottomAnchor, constant: 16),
            statusStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusIndicator.widthAnchor.constraint(equalToConstant: 10),
            statusIndicator.heightAnchor.constraint(equalToConstant: 10),

            actionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            actionLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            actionLabel.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -40),
            actionLabel.heightAnchor.constraint(equalToConstant: 80),

            expiryLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            expiryLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            playerContainerView.widthAnchor.constraint(equalToConstant: 1),
            playerContainerView.heightAnchor.constraint(equalToConstant: 1),
            playerContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerContainerView.topAnchor.constraint(equalTo: view.topAnchor)
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
        
        isRunning = false
        isLagging = false
        disableSystemLag()
        silenceEngine.stop()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.floatingWindow?.isHidden = true
            self.floatingWindow = nil

            self.pipManager?.stop()

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
    @objc func actionLabelTapped() {
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()

        if isRunning {
            isRunning = false
            silenceEngine.stop()

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // Dismiss TrollStore window overlay
                self.floatingWindow?.isHidden = true
                self.floatingWindow = nil

                // Stop Esign PiP overlay
                self.pipManager?.stop()
            }

            disableSystemLag()
            stopVPNTunnel()
            actionLabel.text = "TAP TO START"
            updateStatus(text: "SYSTEM STANDBY", color: UIColor(white: 1.0, alpha: 0.5))
            
            UIView.animate(withDuration: 0.3) {
                self.addGlowToLayer(self.actionLabel.layer, color: UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.8).cgColor, radius: 15)
            }
        } else {
            isRunning = true
            silenceEngine.start()

            let isTrollStoreMode = modeSegmentedControl.selectedSegmentIndex == 0

            if isTrollStoreMode {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    let win = FloatingButtonWindow(actionHandler: { [weak self] in
                        self?.triggerLagCycleFromFloatingButton()
                    })
                    win.isHidden = false
                    self.floatingWindow = win
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if #available(iOS 15.0, *) {
                        if self.pipManager == nil {
                            self.pipManager = PiPOverlayManager(viewController: self)
                        }
                        self.pipManager?.start()
                    } else {
                        print("[FakeLag] PiP is only supported on iOS 15.0 or newer.")
                    }
                }
            }

            startVPNTunnel()
            actionLabel.text = "TAP TO STOP"
            updateStatus(text: "SERVICE RUNNING", color: UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1.0))

            UIView.animate(withDuration: 0.3) {
                self.addGlowToLayer(self.actionLabel.layer, color: UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 0.8).cgColor, radius: 15)
            }
        }
    }

    func triggerLagCycleFromFloatingButton() {
        guard isRunning else { return }
        if isLagging {
            disableSystemLag()
        } else {
            enableSystemLag()
        }
    }

    // MARK: - Lag Tunnel Lifecycle
    func startVPNTunnel() {
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
                        print("[FakeLag] VPN started successfully")
                    } catch {
                        print("[FakeLag] VPN start error: \(error)")
                        LagURLProtocol.isLagEnabled = true
                    }
                }
            }
        }
    }

    func stopVPNTunnel() {
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            managers?.forEach { manager in
                manager.connection.stopVPNTunnel()
            }
        }
        LagURLProtocol.isLagEnabled = false
    }

    // MARK: - Lag Tunnel Activation Controls
    func enableSystemLag() {
        guard !isLagging else { return }
        isLagging = true

        floatingWindow?.setLagActive(true)
        pipManager?.setLagActive(true)

        let defaults = UserDefaults(suiteName: kAppGroup)
        defaults?.set(true, forKey: kLagKey)
        defaults?.synchronize()

        DispatchQueue.main.async { [weak self] in
            self?.onLagEnabled()
        }
    }

    func disableSystemLag() {
        guard isLagging else { return }
        isLagging = false

        floatingWindow?.setLagActive(false)
        pipManager?.setLagActive(false)

        let defaults = UserDefaults(suiteName: kAppGroup)
        defaults?.set(false, forKey: kLagKey)
        defaults?.synchronize()

        DispatchQueue.main.async { [weak self] in
            self?.onLagDisabled()
        }
    }

    private func onLagEnabled() {
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.warning)
        updateStatus(text: "LAG SWITCH ACTIVE (Hi Profile)", color: UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0))
        startStatusPulse()
    }

    private func onLagDisabled() {
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        stopStatusPulse()
        if isRunning {
            updateStatus(text: "SERVICE RUNNING", color: UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1.0))
        } else {
            updateStatus(text: "SYSTEM STANDBY", color: UIColor(white: 1.0, alpha: 0.5))
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
        pulse.toValue = 1.05
        pulse.duration = 1.2
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

    func addGlowToLayer(_ layer: CALayer, color: CGColor, radius: CGFloat) {
        layer.shadowColor = color
        layer.shadowRadius = radius
        layer.shadowOpacity = 1.0
        layer.shadowOffset = .zero
    }
}

// MARK: - PiP Overlay Manager (Requires iOS 15.0+)
@available(iOS 15.0, *)
class PiPOverlayManager: NSObject, PiPManagerProtocol, AVPictureInPictureControllerDelegate {
    weak var viewController: ViewController?
    var pipController: AVPictureInPictureController?
    var player: AVPlayer?
    var playerLayer: AVPlayerLayer?
    private var statusObserver: NSKeyValueObservation?
    
    init(viewController: ViewController) {
        self.viewController = viewController
        super.init()
        setupPiP()
    }
    
    private func setupPiP() {
        guard let vc = viewController, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        
        guard let videoURL = Bundle.main.url(forResource: "blank", withExtension: "mp4") else {
            print("[FakeLag] Error: blank.mp4 not found in main bundle")
            return
        }
        
        let playerItem = AVPlayerItem(url: videoURL)
        let player = AVPlayer(playerItem: playerItem)
        self.player = player
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        vc.playerContainerView.layer.addSublayer(playerLayer)
        self.playerLayer = playerLayer
        
        guard let pipCtrl = AVPictureInPictureController(playerLayer: playerLayer) else {
            print("[FakeLag] Failed to initialize AVPictureInPictureController")
            return
        }
        pipCtrl.delegate = self
        pipCtrl.requiresLinearPlayback = false
        pipCtrl.canStartPictureInPictureAutomaticallyFromInline = true
        self.pipController = pipCtrl
        
        statusObserver = player.observe(\.timeControlStatus, options: [.old, .new]) { [weak self] player, change in
            guard let self = self, let vc = self.viewController else { return }
            DispatchQueue.main.async {
                if player.timeControlStatus == .paused {
                    if vc.isRunning {
                        vc.enableSystemLag()
                    }
                } else if player.timeControlStatus == .playing {
                    vc.disableSystemLag()
                }
            }
        }
    }
    
    @objc private func playerItemDidReachEnd(notification: Notification) {
        player?.seek(to: .zero)
        player?.play()
    }
    
    func start() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[FakeLag] Failed to set audio session for PiP: \(error)")
        }
        player?.play()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.pipController?.startPictureInPicture()
        }
    }
    
    func stop() {
        if pipController?.isPictureInPictureActive == true {
            pipController?.stopPictureInPicture()
        }
        player?.pause()
        statusObserver?.invalidate()
        statusObserver = nil
        NotificationCenter.default.removeObserver(self)
        playerLayer?.removeFromSuperlayer()
    }
    
    func setLagActive(_ active: Bool) {
        guard let player = player else { return }
        DispatchQueue.main.async {
            if active {
                if player.timeControlStatus != .paused {
                    player.pause()
                }
            } else {
                if player.timeControlStatus != .playing {
                    player.play()
                }
            }
        }
    }
    
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("[FakeLag] PiP will start")
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("[FakeLag] PiP did start")
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("[FakeLag] PiP will stop")
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("[FakeLag] PiP did stop")
        if viewController?.isRunning == true {
            viewController?.actionLabelTapped()
        }
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        print("[FakeLag] PiP Failed to Start: \(error.localizedDescription)")
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        print("[FakeLag] PiP restore UI called - blocking restoration")
        completionHandler(false)
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
        
        // Handle iOS 13+ Scene Window registration safely
        if let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }) as? UIWindowScene {
            super.init(windowScene: windowScene)
        } else {
            super.init(frame: initialFrame)
        }
        self.frame = initialFrame
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
        button.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 0.6)
        button.layer.cornerRadius = 40 // 80x80 size
        button.layer.borderWidth = 2.0
        button.layer.borderColor = UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.8).cgColor
        
        // Deep blue outer glow
        button.layer.shadowColor = UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.8).cgColor
        button.layer.shadowOffset = .zero
        button.layer.shadowRadius = 10
        button.layer.shadowOpacity = 0.8
        
        view.addSubview(button)
        
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.topAnchor),
            button.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        
        // Dynamic Pan gesture (Only active in TrollStore UIWindow mode)
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
        // Only allow manual pan dragging if we are running in our custom FloatingButtonWindow (TrollStore mode).
        // For Esign PiP mode, the iOS system PiP controller handles dragging automatically.
        guard let window = view.window, window is FloatingButtonWindow else { return }
        
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

// MARK: - Animated GIF Helper Extension
extension UIImage {
    public class func gifImageWithData(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        
        let count = CGImageSourceGetCount(source)
        var images = [UIImage]()
        var duration = 0.0
        
        for i in 0..<count {
            if let image = CGImageSourceCreateImageAtIndex(source, i, nil) {
                images.append(UIImage(cgImage: image))
            }
            
            let delaySeconds = UIImage.delayForImageAtIndex(Int(i), source: source)
            duration += delaySeconds
        }
        
        if duration == 0.0 {
            duration = Double(count) / 10.0
        }
        
        return UIImage.animatedImage(with: images, duration: duration)
    }

    public class func gifImageWithName(_ name: String) -> UIImage? {
        guard let bundleURL = Bundle.main.url(forResource: name, withExtension: "gif") else { return nil }
        guard let imageData = try? Data(contentsOf: bundleURL) else { return nil }
        return gifImageWithData(imageData)
    }

    private class func delayForImageAtIndex(_ index: Int, source: CGImageSource) -> Double {
        var delay = 0.1
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
              let gifInfo = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] else {
            return delay
        }
        
        if let delayTime = gifInfo[kCGImagePropertyGIFDelayTime as String] as? Double, delayTime > 0 {
            delay = delayTime
        } else if let unclampedDelayTime = gifInfo[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double, unclampedDelayTime > 0 {
            delay = unclampedDelayTime
        }
        
        return delay
    }
}
