import AVFoundation
import Combine
import Foundation
import QuartzCore
import UIKit

final class CaptureObserverStorage {
    var cancellables: Set<AnyCancellable> = []
}

extension LiveStore {
    internal func configureCaptureObservers() {
        observeMotion()
        observeCaptureEvents()
        observeOrientation()
        observeApplicationActivity()
        observeCaptureInterruptions()
        observeRuntimeStatusChanges()
        observeAudioRouteChanges()
    }

    private func observeMotion() {
        motion.$orientation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshGuidanceForMotionIfNeeded() }
            .store(in: &observerStorage.cancellables)
    }

    internal func refreshGuidanceForMotionIfNeeded(at time: CFTimeInterval = CACurrentMediaTime()) {
        guard !requiresFreshLiveSample else {
            motionGuidanceCadence.reset()
            return
        }
        let config = engine.config
        let orientation = motion.orientation
        let boundary = MotionGuidanceCadence.Boundary(
            orientationIsCritical: abs(orientation.rollDegrees) > config.rollCriticalDegrees
                || orientation.pitchDegrees > config.pitchUpCriticalDegrees
                || orientation.pitchDegrees < config.pitchDownCriticalDegrees,
            motionIsAcceptable: motion.motionMetrics.isStable
                && motion.motionMetrics.smoothedAngularSpeed <= config.maxSmoothedAngularSpeed
        )
        guard motionGuidanceCadence.shouldRefresh(at: time, boundary: boundary) else { return }
        recomputeGuidance()
    }

    private func observeCaptureEvents() {
        capture.runtimeEventSink = { [weak self] event in
            // Each producer queue submits runtime facts in source order. These remain a separate,
            // generation-filtered lane from recording transaction lifecycle events.
            DispatchQueue.main.async { [weak self] in self?.handleRuntimeEvent(event) }
        }
        capture.transactionEventSink = { [weak self] event in
            // Transaction events originate on CaptureSessionController.sessionQueue. Dispatching
            // those serial submissions to the main queue preserves their FIFO lifecycle order;
            // unlike an unstructured task per event, later facts cannot overtake earlier ones.
            DispatchQueue.main.async { [weak self] in self?.handleTransactionEvent(event) }
        }
    }

    private func observeOrientation() {
        NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.capture.updateVideoRotation(angle: Self.rotationAngle()) }
            .store(in: &observerStorage.cancellables)
    }

    private func observeApplicationActivity() {
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.appIsActive = false
                self?.privacyCoverIsVisible = true
                // A running take survives transient overlays (Control Center, alerts, Siri);
                // backgrounding and AVFoundation interruptions still finalize it.
                guard self?.activeRecordingTransaction == nil else { return }
                self?.suspend()
            }
            .store(in: &observerStorage.cancellables)
        // Backgrounding always ends a take and starts its finalization background task, without
        // relying on the view tear-down or the AVFoundation interruption arriving first.
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // An earlier suspend already requested the stop and cleared `liveIsActive`.
                guard self?.liveIsActive == true else { return }
                self?.suspend()
            }
            .store(in: &observerStorage.cancellables)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.appIsActive = true
                self?.resumeIfDesired()
            }
            .store(in: &observerStorage.cancellables)
    }

    private func observeCaptureInterruptions() {
        NotificationCenter.default.publisher(for: AVCaptureSession.wasInterruptedNotification, object: capture.session)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.captureIsInterrupted = true
                self?.privacyCoverIsVisible = true
                self?.recordStatusMessage = "Aufnahme unterbrochen - laufende Datei wird finalisiert."
                self?.persistOperationalObservation(
                    kind: .interruption,
                    note: "AVCaptureSession-Unterbrechung; Finalisierung angefordert."
                )
                self?.suspend()
            }
            .store(in: &observerStorage.cancellables)
        NotificationCenter.default.publisher(for: AVCaptureSession.interruptionEndedNotification, object: capture.session)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.captureIsInterrupted = false
                self?.resumeIfDesired()
            }
            .store(in: &observerStorage.cancellables)
        NotificationCenter.default.publisher(for: AVCaptureSession.runtimeErrorNotification, object: capture.session)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleRuntimeError(notification.userInfo?[AVCaptureSessionErrorKey] as? Error)
            }
            .store(in: &observerStorage.cancellables)
    }

    private func observeRuntimeStatusChanges() {
        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshRuntimeStatus() }
            .store(in: &observerStorage.cancellables)
        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshRuntimeStatus() }
            .store(in: &observerStorage.cancellables)
    }

    private func observeAudioRouteChanges() {
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.capture.refreshAudioRouteCache()
                let previousRoute = self?.runtimeStatus.audioRoute
                self?.refreshRuntimeStatus()
                if previousRoute != self?.runtimeStatus.audioRoute { self?.invalidateSpokenAudioCheck() }
                self?.persistOperationalObservation(
                    kind: .audioRouteChange,
                    note: "Audioroute geändert: \(self?.runtimeStatus.audioRoute ?? "nicht verfügbar")"
                )
            }
            .store(in: &observerStorage.cancellables)
    }
}
