//
//  LastRiteFramework.swift
//  LastRiteFramework
//
//  Created by khoahuynhbach on 2/5/26.
//

import Foundation

public final class LastRiteOrchestrator<ActivityMachine, SideEffectMachine, ComputationMachine, QuestionTerminal, CommandGeneratorProvider, SequenceStore>
where ActivityMachine: LastRiteActivityMachine,
      SideEffectMachine: LastRiteSideEffectMachine,
      ComputationMachine: LastRiteComputationMachine,
      QuestionTerminal: LastRiteQuestionTerminal,
      CommandGeneratorProvider: LastRiteCommandGeneratorProvider,
      CommandGeneratorProvider.CommandGenerator.Activity == ActivityMachine.Activity,
      CommandGeneratorProvider.CommandGenerator.SideEffect == SideEffectMachine.SideEffect,
      CommandGeneratorProvider.CommandGenerator.Computation == ComputationMachine.Computation,
      CommandGeneratorProvider.CommandGenerator.Question == QuestionTerminal.Question,
      SequenceStore: LastRiteSequenceStore {
    public typealias Activity = ActivityMachine.Activity
    public typealias SideEffect = SideEffectMachine.SideEffect
    public typealias Computation = ComputationMachine.Computation
    public typealias Question = QuestionTerminal.Question
    
    private let activityMachine: ActivityMachine
    private let sideEffectMachine: SideEffectMachine
    private let computationMachine: ComputationMachine
    private let questionTerminal: QuestionTerminal
    private let generatorProvider: CommandGeneratorProvider
    private let sequenceStore: SequenceStore
    
    private var activeGenerator: CommandGeneratorProvider.CommandGenerator?
    
    private var state: LastRiteOrchestrationState<Activity, SideEffect, Computation, Question>
    
    public init(
        activityMachine: ActivityMachine,
        sideEffectMachine: SideEffectMachine,
        computationMachine: ComputationMachine,
        questionTerminal: QuestionTerminal,
        generatorProvider: CommandGeneratorProvider,
        sequenceStore: SequenceStore
    ) {
        self.activityMachine = activityMachine
        self.sideEffectMachine = sideEffectMachine
        self.computationMachine = computationMachine
        self.questionTerminal = questionTerminal
        self.generatorProvider = generatorProvider
        self.sequenceStore = sequenceStore
        
        self.state = LastRiteOrchestrationState(
            executionState: .idle,
            resettingState: .none,
            isFastForwardingRequested: false,
            isReloading: false
        )
    }

    public func forward() async {
        await dispatch(command: .forward)
    }

    public func reset() async {
        await dispatch(command: .reset)
    }

    public func reload() async {
        await dispatch(command: .reload)
    }
    
    private func dispatch(command: LastRiteOrchestrationCommand<Activity, SideEffect, Computation, Question>) async {
        let effect = state.handle(command: command)
        await run(effect: effect)
    }
    
    private func run(effect: LastRiteOrchestrationEffect<Activity, SideEffect, Computation, Question>) async {
        switch effect {
        case .noop:
            return
            
        case .notifyFastForward:
            await activityMachine.notifyFastForwarding()
            
        case .notifyCancellation:
            await sideEffectMachine.notifyCancellation()
            await computationMachine.notifyCancellation()
            
        case .fetchCommand:
            let command = await activeGenerator?.generate(payload: sequenceStore.last)
            await dispatch(command: .executeCommand(command: command))
            
        case .runActivity(let activity):
            await activityMachine.run(activity: activity)
            await dispatch(command: .notifyActivityCompleted)
            
        case .runSideEffect(let sideEffect):
            await sideEffectMachine.run(sideEffect: sideEffect)
            await dispatch(command: .notifySideEffectCompleted)
            
        case .runComputation(let computation):
            let result = await computationMachine.run(computation: computation)
            await dispatch(command: .notifyComputationCompleted(result: result))
            
        case .askQuestion(let question):
            await questionTerminal.ask(question: question)
            await questionTerminal.show()
        
        case .commitCommand(let payload):
            await sequenceStore.track(value: payload)
            await dispatch(command: .notifyCommandCommitted)
            
        case .commitIdle:
            await sequenceStore.track(value: nil)
            await dispatch(command: .notifyIdleCommitted)
            
        case .performReset:
            await activityMachine.reset()
            await sideEffectMachine.reset()
            await computationMachine.reset()
            await questionTerminal.hide()
            await sequenceStore.clear()
            
            await activeGenerator?.reset()
            
            await dispatch(command: .notifyResetCompleted)
            
        case .performReload(let replayAskQuestion):
            await questionTerminal.hide()
            
            if let newGenerator = await generatorProvider.provide() {
                var payload: (any Sendable)? = nil
                
                for value in await sequenceStore.sequence {
                    _ = await newGenerator.generate(payload: payload)
                    payload = value
                }
                
                if replayAskQuestion, case .askQuestion(let question) = await newGenerator.generate(payload: payload) {
                    await questionTerminal.ask(question: question)
                }
                
                activeGenerator = newGenerator
            }
            
            if replayAskQuestion {
                await questionTerminal.show()
            }
            
            await dispatch(command: .notifyReloadCompleted)
        }
    }
}

public enum LastRiteOrchestrationCommand<Activity, SideEffect, Computation, Question>: Sendable
where Activity: Sendable, SideEffect: Sendable, Computation: Sendable, Question: Sendable {
    case forward
    
    case executeCommand(command: LastRiteCommand<Activity, SideEffect, Computation, Question>?)
    case notifyActivityCompleted
    case notifySideEffectCompleted
    case notifyComputationCompleted(result: (any Sendable)?)
    case submitAnswer(answer: (any Sendable)?)
    case notifyCommandCommitted
    case notifyIdleCommitted
    
    case reset
    case notifyResetCompleted
    
    case reload
    case notifyReloadCompleted
}

public enum LastRiteOrchestrationEffect<Activity, SideEffect, Computation, Question>: Sendable
where Activity: Sendable, SideEffect: Sendable, Computation: Sendable, Question: Sendable {
    case noop
    case notifyFastForward
    case notifyCancellation
    case fetchCommand
    
    case runActivity(activity: Activity)
    case runSideEffect(sideEffect: SideEffect)
    case runComputation(computation: Computation)
    case askQuestion(question: Question)
    case commitCommand(payload: (any Sendable)?)
    case commitIdle
    
    case performReset
    case performReload(replayAskQuestion: Bool)
}

public struct LastRiteOrchestrationState<Activity, SideEffect, Computation, Question>: Sendable
where Activity: Sendable, SideEffect: Sendable, Computation: Sendable, Question: Sendable {
    public var executionState: ExecutionState
    public var resettingState: ResettingState
    public var isFastForwardingRequested: Bool
    public var isReloading: Bool
    
    public init(
        executionState: ExecutionState,
        resettingState: ResettingState,
        isFastForwardingRequested: Bool,
        isReloading: Bool
    ) {
        self.executionState = executionState
        self.resettingState = resettingState
        self.isFastForwardingRequested = isFastForwardingRequested
        self.isReloading = isReloading
    }
    
    public enum ExecutionState: Sendable {
        case idle
        case running
        case waitingForActivityCompletion
        case waitingForSideEffectCompletion
        case waitingForComputationCompletion
        case waitingForAnswer
        case waitingForCommandCommitment
        case waitingForIdleCommitment
    }
    
    public enum ResettingState: Sendable {
        case none
        case resetting
        case waitingForOnGoingSessionCompletion
    }
    
    public mutating func handle(
        command: LastRiteOrchestrationCommand<Activity, SideEffect, Computation, Question>
    ) -> LastRiteOrchestrationEffect<Activity, SideEffect, Computation, Question> {
        switch command {
        case .forward:
            if isReloading || resettingState != .none {
                return .noop
            }
            
            switch executionState {
            case .idle:
                executionState = .running
                return .fetchCommand
                
            case .waitingForActivityCompletion:
                if isFastForwardingRequested {
                    return .noop
                }
                
                isFastForwardingRequested = true
                
                return .notifyFastForward
                
            default:
                return .noop
            }
            
        case .executeCommand(let command):
            if executionState != .running {
                return .noop
            }
            
            if resettingState == .waitingForOnGoingSessionCompletion {
                executionState = .idle
                resettingState = .resetting
                return .performReset
            }
            
            switch command {
            case .none:
                executionState = .idle
                return .noop
                
            case .runActivity(let activity):
                executionState = .waitingForActivityCompletion
                return .runActivity(activity: activity)
                
            case .runSideEffect(let sideEffect):
                executionState = .waitingForSideEffectCompletion
                return .runSideEffect(sideEffect: sideEffect)
                
            case .runComputation(let computation):
                executionState = .waitingForComputationCompletion
                return .runComputation(computation: computation)
                
            case .askQuestion(let question):
                executionState = .waitingForAnswer
                return .askQuestion(question: question)
                
            case .halt:
                executionState = .waitingForIdleCommitment
                return .commitIdle
            }
            
        case .notifyActivityCompleted:
            if executionState != .waitingForActivityCompletion {
                return .noop
            }
            
            isFastForwardingRequested = false
            
            if resettingState == .waitingForOnGoingSessionCompletion {
                executionState = .idle
                resettingState = .resetting
                return .performReset
            }
            
            executionState = .waitingForCommandCommitment
            return .commitCommand(payload: nil)
            
        case .notifySideEffectCompleted:
            if executionState != .waitingForSideEffectCompletion {
                return .noop
            }
            
            if resettingState == .waitingForOnGoingSessionCompletion {
                executionState = .idle
                resettingState = .resetting
                return .performReset
            }
            
            executionState = .waitingForCommandCommitment
            return .commitCommand(payload: nil)
            
        case .notifyComputationCompleted(let result):
            if executionState != .waitingForComputationCompletion {
                return .noop
            }
            
            if resettingState == .waitingForOnGoingSessionCompletion {
                executionState = .idle
                resettingState = .resetting
                return .performReset
            }
            
            executionState = .waitingForCommandCommitment
            return .commitCommand(payload: result)
            
        case .submitAnswer(let answer):
            if isReloading || resettingState != .none {
                return .noop
            }
            
            if executionState != .waitingForAnswer {
                return .noop
            }
            
            executionState = .waitingForCommandCommitment
            return .commitCommand(payload: answer)
            
        case .notifyCommandCommitted:
            if executionState != .waitingForCommandCommitment {
                return .noop
            }
            
            if resettingState == .waitingForOnGoingSessionCompletion {
                executionState = .idle
                resettingState = .resetting
                return .performReset
            }
            
            executionState = .running
            return .fetchCommand
            
        case .notifyIdleCommitted:
            if executionState != .waitingForIdleCommitment {
                return .noop
            }
            
            if resettingState == .waitingForOnGoingSessionCompletion {
                executionState = .idle
                resettingState = .resetting
                return .performReset
            }
            
            executionState = .idle
            return .noop
            
        case .reset:
            if isReloading || resettingState != .none {
                return .noop
            }
            
            switch executionState {
            case .running, .waitingForCommandCommitment, .waitingForIdleCommitment:
                resettingState = .waitingForOnGoingSessionCompletion
                return .noop
                
            case .idle, .waitingForAnswer:
                executionState = .idle
                resettingState = .resetting
                return .performReset
                
            case .waitingForActivityCompletion:
                resettingState = .waitingForOnGoingSessionCompletion
                return .notifyFastForward
                
            case .waitingForSideEffectCompletion, .waitingForComputationCompletion:
                resettingState = .waitingForOnGoingSessionCompletion
                return .notifyCancellation
            }
            
        case .notifyResetCompleted:
            if resettingState != .resetting {
                return .noop
            }
            
            resettingState = .none
            
            return .noop
            
        case .reload:
            if isReloading || resettingState != .none {
                return .noop
            }
            
            if executionState != .idle && executionState != .waitingForAnswer {
                return .noop
            }
            
            isReloading = true
            
            return .performReload(replayAskQuestion: executionState == .waitingForAnswer)
            
        case .notifyReloadCompleted:
            if !isReloading {
                return .noop
            }
            
            isReloading = false
            
            return .noop
        }
    }
}
