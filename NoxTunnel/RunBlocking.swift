import Foundation

/// libbox calls the platform interface synchronously from Go threads; NetworkExtension APIs
/// are async. Blocks the calling (Go) thread until the async work finishes.
func runBlocking<T>(_ block: @escaping @Sendable () async -> T) -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let box = ResultBox<T>()
    Task.detached {
        box.value = .success(await block())
        semaphore.signal()
    }
    semaphore.wait()
    return try! box.value!.get()
}

func runBlocking<T>(_ block: @escaping @Sendable () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let box = ResultBox<T>()
    Task.detached {
        do {
            box.value = .success(try await block())
        } catch {
            box.value = .failure(error)
        }
        semaphore.signal()
    }
    semaphore.wait()
    return try box.value!.get()
}

private final class ResultBox<T>: @unchecked Sendable {
    var value: Result<T, Error>?
}
