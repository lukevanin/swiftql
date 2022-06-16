import Foundation
import OSLog
import Combine


private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "swiftql")


class ObservableStatement<T>: Publisher {
    typealias Failure = Error
    
    typealias Output = Result<[T], Error>
    
    // TODO: Raise error when database connection is closed
    
    private var eventCancellable: AnyCancellable?
    private let statement: PreparedSQL<T>
    private let provider: SQLProviderProtocol
    private let subject: CurrentValueSubject<Output, Failure>
    
    init(statement: PreparedSQL<T>, provider: SQLProviderProtocol) {
        logger.debug("observable statement > init > start")
        self.statement = statement
        self.provider = provider
        self.subject = CurrentValueSubject(.success([]))
        

        // TODO: Attach to database event and re-run query when database transaction is committed.
        // TODO: Use async sequence instead of publisher to observe events.
        eventCancellable = provider.eventsPublisher.sink(
            receiveCompletion: { completion in
                
            },
            receiveValue: { [weak self] event in
                logger.debug("observable statement > event : \(event.rawValue)")
                if event == .commit {
                    self?.invalidate()
                }
            }
        )
        invalidate()
        logger.debug("observable statement > init > end")
    }
    
    deinit {
        logger.debug("observable statement > deinit")
        eventCancellable?.cancel()
    }
    
    func receive<S>(subscriber: S) where S : Subscriber, S.Input == Output, S.Failure == Failure {
        subject.receive(subscriber: subscriber)
    }
    
    private func invalidate() {
        Task { [weak self] in
            guard let self = self else {
                return
            }
            try await self.provider.transaction { [weak self] transaction in
                guard let self = self else {
                    return
                }
                logger.debug("observable statement > invalidate")
                let value: Output
                do {
                    let result = try self.statement.execute()
                    value = .success(result)
                }
                catch {
                    value = .failure(error)
                }
                self.subject.send(value)
            }
        }
    }
}

