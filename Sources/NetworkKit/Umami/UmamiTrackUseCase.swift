//
//  UmamiTrackUseCase.swift
//  NetworkKit
//
//  Upstreamed from WabiSabi (Core/Abstracts/Domain/UseCases) — 2026-09-09.
//  Executes an ``UmamiEndPoint/track`` call through the injected
//  ``NetworkProtocol`` and returns the decoded ``UmamiAnswer``. Any
//  ``NetworkError`` is mapped to ``TrackUseCaseError/networkError``.
//

import CoreKit
import Foundation

public struct UmamiTrackUseCase: TrackUseCaseProtocol {
  public typealias ResponseModel = UmamiAnswer

  private let networkService: NetworkProtocol
  private let config: UmamiConfig

  public init(networkService: NetworkProtocol, config: UmamiConfig) {
    self.networkService = networkService
    self.config = config
  }

  @discardableResult
  public func execute(_ params: TrackInfoProtocol) async throws(TrackUseCaseError) -> UmamiAnswer {
    let endPoint = UmamiEndPoint.track(
      config: config,
      url: params.url,
      title: params.title,
      referrer: params.referrer,
      tag: params.tag,
      params: params.extra
    )
    do {
      let answer: UmamiAnswer = try await networkService.sendRequest(endpoint: endPoint)
      AppLog.tracking.info("Track success: \(String(describing: endPoint))")
      return answer
    } catch let error as NetworkError {
      AppLog.tracking.error("Track error: \(error.description)")
      throw .networkError
    } catch {
      AppLog.tracking.error("Track error: \(error.localizedDescription)")
      throw .networkError
    }
  }
}
