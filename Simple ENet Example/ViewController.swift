import UIKit

/**
 * Allows user to connect to an ENet server and send UTF-8 text back and forth.
 */

class ViewController: UIViewController {

    @IBOutlet weak var label: UILabel!    
    @IBOutlet weak var serverTextField: UITextField!
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var disconnectButton: UIButton!
    @IBOutlet weak var outboxTextView: UITextView!
    @IBOutlet weak var inboxTextView: UITextView!
    @IBOutlet weak var sendButton: UIButton!
    
    var client: UnsafeMutablePointer<ENetHost>?
    var peer: UnsafeMutablePointer<ENetPeer>?

    var serviceTimer: Timer?
    var serviceIterations = 0.0
    let connectionTimeoutSeconds = 10.0
    let serviceTimeInterval = 0.25

    enum State: String {
        case connecting = "Connecting..."
        case connected = "Connected"
        case disconnected = "Not Connected"
    }
    
    var state: State = .disconnected {
        didSet {
            label.text = state.rawValue
            
            inboxTextView.text = nil
            
            switch state {
            case .connecting:
                serverTextField.isHidden = true
                connectButton.isHidden = true
                disconnectButton.isHidden = true
                outboxTextView.isHidden = true
                inboxTextView.isHidden = true
                sendButton.isHidden = true
                
            case .connected:
                serverTextField.isHidden = true
                connectButton.isHidden = true
                disconnectButton.isHidden = false
                outboxTextView.isHidden = false
                inboxTextView.isHidden = false
                sendButton.isHidden = false
                outboxTextView.becomeFirstResponder()
                
            case .disconnected:
                serverTextField.isHidden = false
                connectButton.isHidden = false
                disconnectButton.isHidden = true
                outboxTextView.isHidden = true
                sendButton.isHidden = true
                inboxTextView.isHidden = true
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        state = .disconnected
    }
    
    func didReceive(_ data: Data) {
        if let text = String(data: data, encoding: .utf8) {
            inboxTextView.text = text
        }
    }
    
    @IBAction func disconnect(_ sender: Any) {
        if let client = client {
            enet_host_destroy(client)
        }
        
        serviceTimer?.invalidate()
        
        state = .disconnected
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        disconnect(self)
    }
    
    @IBAction func connect(_ sender: UIButton) {
        let addr = UnsafeMutablePointer<ENetAddress>.allocate(capacity: 1)

        if let parts = serverTextField.text?.split(separator: ":") {
            guard parts.count > 0 else {
                return
            }
            
            var port: UInt16 = 3000
            
            if parts.count == 2 {
                if let parsed = UInt16(parts.last!) {
                    port = parsed
                }
            }

            addr.pointee.port = port
            
            enet_address_set_host(addr, parts.first!.cString(using: .utf8))
        }
        
        state = .connecting
        
        client = enet_host_create(nil, 1, 2, 0, 0)
        peer = enet_host_connect(client, addr, 2, 0)
        
        serviceIterations = 0
        
        serviceTimer = Timer.scheduledTimer(timeInterval: serviceTimeInterval, target: self, selector: #selector(serviceClientHost), userInfo: nil, repeats: true)
    }
    
    @objc func serviceClientHost() {
        serviceIterations += 1
        
        if state == .connecting && serviceIterations > connectionTimeoutSeconds / serviceTimeInterval {
            self.disconnect(self)
            return
        }
        
        let event = UnsafeMutablePointer<ENetEvent>.allocate(capacity: 1)
        
        while (enet_host_service(self.client, event, 0) > 0) {
            switch event.pointee.type {
            case ENET_EVENT_TYPE_CONNECT:
                state = .connected

            case ENET_EVENT_TYPE_RECEIVE:
                didReceive(Data(
                    bytes: event.pointee.packet.pointee.data,
                    count: event.pointee.packet.pointee.dataLength))
                
            case ENET_EVENT_TYPE_DISCONNECT:
                state = .disconnected

            default:
                break
            }
        }
    }

    @IBAction func sendMessage(_ sender: Any) {
        guard let peer = peer,
            let payload = outboxTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return
        }
        
        let packet = enet_packet_create(payload, payload.lengthOfBytes(using: .utf8), ENET_PACKET_FLAG_RELIABLE.rawValue)
        
        enet_peer_send(peer, 0, packet)
    }
}
