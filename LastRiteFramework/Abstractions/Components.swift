//
//  Components.swift
//  LastRiteFramework
//
//  Created by khoahuynhbach on 2/5/26.
//

public protocol LastRiteActivityMachine<Activity> {
    associatedtype Activity: Sendable
    
    func run(activity: Activity) async
    func notifyFastForwarding() async
    func reset() async
}

public protocol LastRiteSideEffectMachine<SideEffect> {
    associatedtype SideEffect: Sendable
    
    func run(sideEffect: SideEffect) async
    func notifyCancellation() async
    func reset() async
}

public protocol LastRiteComputationMachine<Computation> {
    associatedtype Computation: Sendable
    
    func run(computation: Computation) async -> (any Sendable)?
    func notifyCancellation() async
    func reset() async
}

public protocol LastRiteQuestionTerminal<Question> {
    associatedtype Question: Sendable
    
    func ask(question: Question) async
    func show() async
    func hide() async
}
