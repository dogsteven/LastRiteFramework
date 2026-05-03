# LastRite — Product Requirements
## Problem
Building interactive, scripted experiences — children's books, guided tutorials, adaptive presentations — requires coordinating many kinds of actions: things the user watches, things that happen behind the scenes, decisions the experience needs to make, and moments where the user must respond. Without a clear model for this, developers end up tangling these concerns together, making scripts hard to write, reason about, and iterate on.

There is also a practical authoring problem: when developing such an experience, every script change currently requires restarting from the beginning to see the effect. For experiences with any length or depth, this makes iteration painful.

## Users
**Experience authors** write and maintain scripts. They think in terms of story beats, branching logic, and user interaction — not infrastructure. They want to express what happens and in what order, without worrying about how the interpreter manages it.

**Experience developers** integrate LastRite into a product. They configure what each command type means in their context — what an "activity" looks like in their UI, where "side effects" go, what "computation" means for their data model.

**End users** are the audience of the finished experience — children reading an interactive book, learners going through a tutorial, attendees of a guided presentation.

## User Stories
### Authoring
> As an experience author, I want to write a script as a simple sequence of steps, so that I can think about the experience linearly without worrying about timing or coordination.
> 
> As an experience author, I want to issue a question and have the user's answer available at the next step, so that I can write experiences that branch based on real input.
>
> As an experience author, I want to request a runtime value and have it available at the next step, so that I can make decisions based on the current state of the experience.
>
> As an experience author, I want to deliberately pause the experience at a chosen point and resume it later, so that I can structure an experience with natural boundaries like chapters or sections.
>
> As an experience author, I want to mark certain steps as skippable, so that impatient or returning users can move through familiar content without waiting for it to finish.
>
> As an experience author, I want to update my script and immediately see the effect at my current position in the experience, so that I can iterate quickly without replaying the entire experience from the start every time I make a change.

### End User
> As an end user, I want to skip through an animation or narration I have already seen, so that I can move at my own pace.
> 
> As an end user, I want my progress to be preserved when I restart an experience, so that I do not lose what I have already done.
> 
> As an end user, I want the experience to respond differently based on answers I give, so that it feels relevant to me personally.

## Requirements
**The interpreter must be strictly serial**. Only one step is ever executing at a time. Authors write scripts with the assumption that each step completes before the next begins.

**Fast-forward must be scoped to skippable content**. The ability to skip applies only to steps the author has designated as skippable. It must have no effect on anything else — background actions, computations, or moments where the user is being asked something.

**Questions must block progression**. The experience must not advance past a question until the user has provided an answer.

**Hot reload must preserve position**. Swapping in an updated script must not force the author back to the beginning. The experience resumes at the same point it was at before the update.

**Reset must produce a clean slate**. After a reset, the experience is in exactly the same state as if it had never been started.

**The authoring model must be independent of the delivery platform**. A script written for an interactive book should not contain assumptions about how activities are rendered, where data is stored, or what a question looks like on screen. These are the concerns of the developer integrating LastRite, not the author writing the script.
