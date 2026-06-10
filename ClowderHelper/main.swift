import Foundation
import HelperProtocol

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let service = HelperService()

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard ConnectionValidator.isValid(connection) else { return false }
        connection.exportedInterface = NSXPCInterface(with: ClowderHelperProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
delegate.service.start()
listener.resume()
RunLoop.main.run()
