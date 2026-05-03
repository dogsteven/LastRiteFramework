//
//  Scripting.swift
//  LastRiteFramework
//
//  Created by khoahuynhbach on 2/5/26.
//

public enum LastRiteCommand<Activity, SideEffect, Computation, Question>: Sendable
where Activity: Sendable, SideEffect: Sendable, Computation: Sendable, Question: Sendable {
    case runActivity(activity: Activity)
    case runSideEffect(sideEffect: SideEffect)
    case runComputation(computation: Computation)
    case askQuestion(question: Question)
    case halt
}

public protocol LastRiteCommandGenerator<Activity, SideEffect, Computation, Question> {
    associatedtype Activity: Sendable
    associatedtype SideEffect: Sendable
    associatedtype Computation: Sendable
    associatedtype Question: Sendable
    
    func generate(payload: (any Sendable)?) async -> LastRiteCommand<Activity, SideEffect, Computation, Question>?
    func reset() async
}

public protocol LastRiteCommandGeneratorProvider<CommandGenerator> {
    associatedtype CommandGenerator: LastRiteCommandGenerator
    
    func provide() async -> CommandGenerator?
}

public protocol LastRiteSequenceStore {
    func track(value: (any Sendable)?) async
    func clear() async
    
    var last: (any Sendable)? { get async }
    var sequence: any Sequence<(any Sendable)?> { get async }
}


extension LastRiteCommand: Decodable where Activity: Decodable, SideEffect: Decodable, Computation: Decodable, Question: Decodable {}
