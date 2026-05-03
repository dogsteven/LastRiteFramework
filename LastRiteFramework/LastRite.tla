---- MODULE LastRite ----
EXTENDS Naturals, TLC

(* =================== TYPE DEFINITIONS =================== *)

ExecutionStates == {
    "idle", "running",
    "waitingForActivityCompletion",
    "waitingForSideEffectCompletion",
    "waitingForComputationCompletion",
    "waitingForAnswer",
    "waitingForCommandCommitment",
    "waitingForIdleCommitment"
}

ResettingStates == { "none", "resetting", "waitingForOnGoingSessionCompletion" }

CommandTypes == {
    "none", "runActivity", "runSideEffect",
    "runComputation", "askQuestion", "halt"
}

EffectTypes == {
    "noop", "notifyFastForward", "notifyCancellation",
    "fetchCommand", "runActivity", "runSideEffect", "runComputation", "askQuestion",
    "commitCommand", "commitIdle",
    "performReset", "performReloadWithoutReplayingAskQuestion", "performReloadWithReplayingAskQuestion"
}

(* =================== STATE VARIABLES =================== *)

VARIABLES
    executionState,
    resettingState,
    isFastForwardingRequested,
    isReloading,
    lastEffect

vars == << executionState, resettingState, isFastForwardingRequested,
           isReloading, lastEffect >>

(* =================== TYPE INVARIANT =================== *)

TypeOK ==
    /\ executionState \in ExecutionStates
    /\ resettingState \in ResettingStates
    /\ isFastForwardingRequested \in BOOLEAN
    /\ isReloading \in BOOLEAN
    /\ lastEffect \in EffectTypes

(* =================== INITIAL STATE =================== *)

Init ==
    /\ executionState = "idle"
    /\ resettingState = "none"
    /\ isFastForwardingRequested = FALSE
    /\ isReloading = FALSE
    /\ lastEffect = "noop"

(* =================== TRANSITIONS =================== *)

\* forward
HandleForward ==
    /\ ~isReloading
    /\ resettingState = "none"
    /\ \/ \* idle -> running, fetch command
          ( /\ executionState = "idle"
            /\ executionState' = "running"
            /\ lastEffect' = "fetchCommand"
            /\ UNCHANGED << resettingState, isFastForwardingRequested, isReloading >> )
       \/ \* waiting for activity, first fast-forward request
          ( /\ executionState = "waitingForActivityCompletion"
            /\ ~isFastForwardingRequested
            /\ isFastForwardingRequested' = TRUE
            /\ lastEffect' = "notifyFastForward"
            /\ UNCHANGED << executionState, resettingState, isReloading >> )
       \/ \* already fast-forwarding: noop
          ( /\ executionState = "waitingForActivityCompletion"
            /\ isFastForwardingRequested
            /\ lastEffect' = "noop"
            /\ UNCHANGED << executionState, resettingState, isFastForwardingRequested, isReloading >> )
       \/ \* all other states: noop
          ( /\ executionState \notin {"idle", "waitingForActivityCompletion"}
            /\ lastEffect' = "noop"
            /\ UNCHANGED << executionState, resettingState, isFastForwardingRequested, isReloading >> )

\* executeCommand(command)
HandleExecuteCommand(command) ==
    /\ executionState = "running"
    /\ \/ \* reset pending: intercept and perform reset
          ( /\ resettingState = "waitingForOnGoingSessionCompletion"
            /\ executionState' = "idle"
            /\ resettingState' = "resetting"
            /\ lastEffect' = "performReset"
            /\ UNCHANGED << isFastForwardingRequested, isReloading >> )
       \/ \* normal dispatch by command type
          ( /\ resettingState # "waitingForOnGoingSessionCompletion"
            /\ CASE command = "none" ->
                    \* nil command: go idle silently, no commit needed
                    /\ executionState' = "idle"
                    /\ lastEffect' = "noop"
                    /\ UNCHANGED << resettingState, isFastForwardingRequested, isReloading >>
                 [] command = "runActivity" ->
                    /\ executionState' = "waitingForActivityCompletion"
                    /\ lastEffect' = "runActivity"
                    /\ UNCHANGED << resettingState, isFastForwardingRequested, isReloading >>
                 [] command = "runSideEffect" ->
                    /\ executionState' = "waitingForSideEffectCompletion"
                    /\ lastEffect' = "runSideEffect"
                    /\ UNCHANGED << resettingState, isFastForwardingRequested, isReloading >>
                 [] command = "runComputation" ->
                    /\ executionState' = "waitingForComputationCompletion"
                    /\ lastEffect' = "runComputation"
                    /\ UNCHANGED << resettingState, isFastForwardingRequested, isReloading >>
                 [] command = "askQuestion" ->
                    /\ executionState' = "waitingForAnswer"
                    /\ lastEffect' = "askQuestion"
                    /\ UNCHANGED << resettingState, isFastForwardingRequested, isReloading >>
                 [] command = "halt" ->
                    /\ executionState' = "waitingForIdleCommitment"
                    /\ lastEffect' = "commitIdle"
                    /\ UNCHANGED << resettingState, isFastForwardingRequested, isReloading >> )

\* notifyActivityCompleted
HandleNotifyActivityCompleted ==
    /\ executionState = "waitingForActivityCompletion"
    /\ isFastForwardingRequested' = FALSE
    /\ \/ ( /\ resettingState = "waitingForOnGoingSessionCompletion"
            /\ executionState' = "idle"
            /\ resettingState' = "resetting"
            /\ lastEffect' = "performReset"
            /\ UNCHANGED << isReloading >> )
       \/ ( /\ resettingState # "waitingForOnGoingSessionCompletion"
            /\ executionState' = "waitingForCommandCommitment"
            /\ lastEffect' = "commitCommand"
            /\ UNCHANGED << resettingState, isReloading >> )

\* notifySideEffectCompleted
HandleNotifySideEffectCompleted ==
    /\ executionState = "waitingForSideEffectCompletion"
    /\ \/ ( /\ resettingState = "waitingForOnGoingSessionCompletion"
            /\ executionState' = "idle"
            /\ resettingState' = "resetting"
            /\ lastEffect' = "performReset"
            /\ UNCHANGED << isFastForwardingRequested, isReloading >> )
       \/ ( /\ resettingState # "waitingForOnGoingSessionCompletion"
            /\ executionState' = "waitingForCommandCommitment"
            /\ lastEffect' = "commitCommand"
            /\ UNCHANGED << resettingState, isFastForwardingRequested, isReloading >> )

\* notifyComputationCompleted
HandleNotifyComputationCompleted ==
    /\ executionState = "waitingForComputationCompletion"
    /\ \/ ( /\ resettingState = "waitingForOnGoingSessionCompletion"
            /\ executionState' = "idle"
            /\ resettingState' = "resetting"
            /\ lastEffect' = "performReset"
            /\ UNCHANGED << isFastForwardingRequested, isReloading >> )
       \/ ( /\ resettingState # "waitingForOnGoingSessionCompletion"
            /\ executionState' = "waitingForCommandCommitment"
            /\ lastEffect' = "commitCommand"
            /\ UNCHANGED << resettingState, isFastForwardingRequested, isReloading >> )

\* submitAnswer
HandleSubmitAnswer ==
    /\ ~isReloading
    /\ resettingState = "none"
    /\ executionState = "waitingForAnswer"
    /\ executionState' = "waitingForCommandCommitment"
    /\ lastEffect' = "commitCommand"
    /\ UNCHANGED << resettingState, isFastForwardingRequested, isReloading >>

\* notifyCommandCommitted
HandleNotifyCommandCommitted ==
    /\ executionState = "waitingForCommandCommitment"
    /\ \/ ( /\ resettingState = "waitingForOnGoingSessionCompletion"
            /\ executionState' = "idle"
            /\ resettingState' = "resetting"
            /\ lastEffect' = "performReset"
            /\ UNCHANGED << isFastForwardingRequested, isReloading >> )
       \/ ( /\ resettingState # "waitingForOnGoingSessionCompletion"
            /\ executionState' = "running"
            /\ lastEffect' = "fetchCommand"
            /\ UNCHANGED << resettingState, isFastForwardingRequested, isReloading >> )

\* notifyIdleCommitted
HandleNotifyIdleCommitted ==
    /\ executionState = "waitingForIdleCommitment"
    /\ \/ ( /\ resettingState = "waitingForOnGoingSessionCompletion"
            /\ executionState' = "idle"
            /\ resettingState' = "resetting"
            /\ lastEffect' = "performReset"
            /\ UNCHANGED << isFastForwardingRequested, isReloading >> )
       \/ ( /\ resettingState # "waitingForOnGoingSessionCompletion"
            /\ executionState' = "idle"
            /\ lastEffect' = "noop"
            /\ UNCHANGED << resettingState, isFastForwardingRequested, isReloading >> )

\* reset
HandleReset ==
    /\ ~isReloading
    /\ resettingState = "none"
    /\ CASE executionState \in {"running", "waitingForCommandCommitment",
                                "waitingForIdleCommitment"} ->
                /\ resettingState' = "waitingForOnGoingSessionCompletion"
                /\ lastEffect' = "noop"
                /\ UNCHANGED << executionState, isFastForwardingRequested, isReloading >>
            [] executionState \in {"idle", "waitingForAnswer"} ->
                /\ executionState' = "idle"
                /\ resettingState' = "resetting"
                /\ lastEffect' = "performReset"
                /\ UNCHANGED << isFastForwardingRequested, isReloading >>
            [] executionState = "waitingForActivityCompletion" ->
                /\ resettingState' = "waitingForOnGoingSessionCompletion"
                /\ isFastForwardingRequested' = TRUE
                /\ lastEffect' = "notifyFastForward"
                /\ UNCHANGED << executionState, isReloading >>
            [] executionState \in {"waitingForSideEffectCompletion",
                                   "waitingForComputationCompletion"} ->
                /\ resettingState' = "waitingForOnGoingSessionCompletion"
                /\ lastEffect' = "notifyCancellation"
                /\ UNCHANGED << executionState, isFastForwardingRequested, isReloading >>

\* notifyResetCompleted
HandleNotifyResetCompleted ==
    /\ resettingState = "resetting"
    /\ resettingState' = "none"
    /\ lastEffect' = "noop"
    /\ UNCHANGED << executionState, isFastForwardingRequested, isReloading >>

\* reload
HandleReload ==
    /\ ~isReloading
    /\ resettingState = "none"
    /\ executionState \in {"idle", "waitingForAnswer"}
    /\ isReloading' = TRUE
    /\ ( IF executionState = "waitingForAnswer"
         THEN lastEffect' = "performReloadWithReplayingAskQuestion"
         ELSE lastEffect' = "performReloadWithoutReplayingAskQuestion" )
    /\ UNCHANGED << executionState, resettingState, isFastForwardingRequested >>

\* notifyReloadCompleted
HandleNotifyReloadCompleted ==
    /\ isReloading
    /\ isReloading' = FALSE
    /\ lastEffect' = "noop"
    /\ UNCHANGED << executionState, resettingState, isFastForwardingRequested >>

(* =================== NEXT STATE =================== *)

Next ==
    \/ HandleForward
    \/ \E cmd \in CommandTypes : HandleExecuteCommand(cmd)
    \/ HandleNotifyActivityCompleted
    \/ HandleNotifySideEffectCompleted
    \/ HandleNotifyComputationCompleted
    \/ HandleSubmitAnswer
    \/ HandleNotifyCommandCommitted
    \/ HandleNotifyIdleCommitted
    \/ HandleReset
    \/ HandleNotifyResetCompleted
    \/ HandleReload
    \/ HandleNotifyReloadCompleted

Spec == Init /\ [][Next]_vars

(* =================== SAFETY PROPERTIES =================== *)

Invariant0_AdvanceIsOnlyBeFiredOnRunning ==
    lastEffect = "advance" => executionState = "running"

Invariant1_FastForwardIsOnlyBeFiredOnWaitingForActivityCompletion ==
    lastEffect = "notifyFastForward" => executionState = "waitingForActivityCompletion"

Invariant2_RunActivityIsOnlyBeFiredOnWaitingForActivityCompletion ==
    lastEffect = "runActivity" => executionState = "waitingForActivityCompletion"

Invariant3_RunSideEffectIsOnlyBeFiredOnWaitingForSideEffectCompletion ==
    lastEffect = "runSideEffect" => executionState = "waitingForSideEffectCompletion"

Invariant4_RunComputationIsOnlyBeFiredOnWaitingForComputationCompletion ==
    lastEffect = "runComputation" => executionState = "waitingForComputationCompletion"

Invariant5_AskQuestionIsOnlyBeFiredOnWaitingForAnswer ==
    lastEffect = "askQuestion" => executionState = "waitingForAnswer"

Invariant6_CompleteCommandIsOnlyBeFiredOnWaitingForCommandCompletion ==
    lastEffect \in {"completeCommand", "completeIdle"} => executionState = "waitingForCommandCompletion"

Invanrant7_PerformResetIsOnlyBeFiredOnResetting ==
    lastEffect = "performReset" <=> resettingState = "resetting"

Invariant8_IdleDuringResetting ==
    resettingState = "resetting" => executionState = "idle"

Invariant9_WaitingForOnGoingSessionCompletionOnlyHoldsOnValidPoints ==
    resettingState = "waitingForOnGoingSessionCompletion" => executionState \notin {"idle", "waitingForAnswer"}

Invariant10_NotifyCancellationIsOnlyBeFiredOnValidPoints ==
    lastEffect = "notifyCancellation" => (
        /\ executionState \in {"waitingForSideEffectCompletion", "waitingForComputationCompletion"}
        /\ resettingState = "waitingForOnGoingSessionCompletion"
    )

Invariant11_PerformReloadIsOnlyFiredOnReloading ==
    lastEffect \in {"performReloadWithoutReplayingAskQuestion", "performReloadWithReplayingAskQuestion"} <=> isReloading

Invariant12_IsReloadingOnlyHoldsOnIdleOrWaitingForAnswer ==
    isReloading => executionState \in {"idle", "waitingForAnswer"}

Invariant12_PerformReloadWithReplayingAsQuestionIsOnlyBeFiredOnWaitingForAnswer ==
    lastEffect = "performReloadWithReplayingAskQuestion" => executionState = "waitingForAnswer"

Invariant13_PerformReloadWithoutReplayingAsQuestionIsOnlyBeFiredOnIdle ==
    lastEffect = "performReloadWithoutReplayingAskQuestion" => executionState = "idle"

Invariant14_ExclusivityOfReloadingAndResetting ==
    isReloading => resettingState = "none"

Invariant15_IsFastForwardRequestedOnlyHoldsOnWaitingForActivityCompletion ==
    isFastForwardingRequested => executionState = "waitingForActivityCompletion"

(* =================== COMBINED INVARIANT =================== *)

AllInvariants ==
    /\ TypeOK
    /\ Invariant0_AdvanceIsOnlyBeFiredOnRunning
    /\ Invariant1_FastForwardIsOnlyBeFiredOnWaitingForActivityCompletion
    /\ Invariant2_RunActivityIsOnlyBeFiredOnWaitingForActivityCompletion
    /\ Invariant3_RunSideEffectIsOnlyBeFiredOnWaitingForSideEffectCompletion
    /\ Invariant4_RunComputationIsOnlyBeFiredOnWaitingForComputationCompletion
    /\ Invariant5_AskQuestionIsOnlyBeFiredOnWaitingForAnswer
    /\ Invariant6_CompleteCommandIsOnlyBeFiredOnWaitingForCommandCompletion
    /\ Invanrant7_PerformResetIsOnlyBeFiredOnResetting
    /\ Invariant8_IdleDuringResetting
    /\ Invariant9_WaitingForOnGoingSessionCompletionOnlyHoldsOnValidPoints
    /\ Invariant10_NotifyCancellationIsOnlyBeFiredOnValidPoints
    /\ Invariant11_PerformReloadIsOnlyFiredOnReloading
    /\ Invariant12_IsReloadingOnlyHoldsOnIdleOrWaitingForAnswer
    /\ Invariant12_PerformReloadWithReplayingAsQuestionIsOnlyBeFiredOnWaitingForAnswer
    /\ Invariant13_PerformReloadWithoutReplayingAsQuestionIsOnlyBeFiredOnIdle
    /\ Invariant14_ExclusivityOfReloadingAndResetting
    /\ Invariant15_IsFastForwardRequestedOnlyHoldsOnWaitingForActivityCompletion

(* =================== LIVENESS PROPERTIES =================== *)
Fairness ==
    /\ WF_vars(HandleReset)
    /\ WF_vars(HandleNotifyResetCompleted)
    /\ WF_vars(HandleReload)
    /\ WF_vars(HandleNotifyReloadCompleted)
    /\ WF_vars(HandleNotifyActivityCompleted)
    /\ WF_vars(HandleNotifySideEffectCompleted)
    /\ WF_vars(HandleNotifyComputationCompleted)
    /\ WF_vars(HandleNotifyCommandCommitted)
    /\ WF_vars(HandleNotifyIdleCommitted)
    /\ WF_vars(HandleForward)
    /\ WF_vars(HandleSubmitAnswer)
    /\ \A cmd \in CommandTypes : WF_vars(HandleExecuteCommand(cmd))

LiveSpec == Spec /\ Fairness

EventuallyLeavesRunning ==
    [](executionState = "running" ~> executionState # "running")

CommandEventuallyCompletes ==
    [](executionState = "waitingForCommandCompletion" ~> executionState \in {"idle", "running"})

ResetEventuallyCompletes ==
    [](resettingState = "resetting" ~> resettingState = "none")

ReloadEventuallyCompletes ==
    [](isReloading ~> ~isReloading)
=================================================================
