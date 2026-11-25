//! Two calls at once, as Teams' Consult then transfer and Merge Calls use
//! them: the call you're in is put on hold, a second (consult) call is
//! placed to someone, and from there you transfer the first call to them
//! (the transfer names the consult call it replaces) or merge both calls
//! into one group call.
//!
//! This is the state both calls go through; the call window and the
//! backend follow it.

/// Where a consult stands.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub enum Consult {
    /// One call (no consult).
    #[default]
    Idle,
    /// The first call is held and the consult call is ringing `target`.
    Placing { target: Person },
    /// Talking with `target` while the first call waits on hold.
    Connected { target: Person },
    /// Transfer sent: the first call goes to `target`, replacing the
    /// consult call.
    Transferring { target: Person },
    /// Merge sent: everyone joins the consult call as a group call.
    Merging { target: Person },
}

/// Who the consult is with.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Person {
    /// `8:orgid:<oid>`.
    pub mri: String,
    pub name: String,
}

/// What happened to the calls.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Event {
    /// You picked someone and chose Start a call.
    Start(Person),
    /// They answered the consult call.
    Answered,
    /// You pressed Transfer.
    Transfer,
    /// You pressed Merge Calls.
    Merge,
    /// The consult call ended (they hung up, didn't answer, or you ended
    /// the consult): back to the held call.
    ConsultEnded,
    /// The transfer completed (`transferCompletion` code 0) or the merge
    /// was accepted: the consult is over.
    Done,
    /// The transfer or merge failed: the consult call carries on.
    Failed,
}

/// What the backend should do after a transition.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Action {
    /// Put the first call on hold and place the consult call.
    HoldAndCall,
    /// Send the first call's transfer naming the consult call it replaces.
    SendTransfer,
    /// Merge the first call's people into the consult call, then leave the
    /// first call.
    SendMerge,
    /// The consult is over and the first call is still there: take it off
    /// hold (Teams' Resume) and show it.
    ResumeFirst,
    /// Both calls are finished for us (transferred, or merged into the
    /// consult call, which goes on as the group call).
    Finished,
    /// Nothing to do (an event that doesn't apply now).
    Nothing,
}

impl Consult {
    /// Apply `event`; the new state and what to do.
    pub fn step(&self, event: Event) -> (Consult, Action) {
        use Consult::*;
        match (self, event) {
            (Idle, Event::Start(p)) => (Placing { target: p }, Action::HoldAndCall),
            (Placing { target }, Event::Answered) => (
                Connected {
                    target: target.clone(),
                },
                Action::Nothing,
            ),
            (Connected { target }, Event::Transfer) => (
                Transferring {
                    target: target.clone(),
                },
                Action::SendTransfer,
            ),
            (Connected { target }, Event::Merge) => (
                Merging {
                    target: target.clone(),
                },
                Action::SendMerge,
            ),
            (Transferring { target } | Merging { target }, Event::Failed) => (
                Connected {
                    target: target.clone(),
                },
                Action::Nothing,
            ),
            (Transferring { .. }, Event::Done) => (Idle, Action::Finished),
            // A merge leaves us in the consult call, now the group call.
            (Merging { .. }, Event::Done) => (Idle, Action::Finished),
            // The consult call is replaced by the transfer: its end is the
            // transfer's, not a reason to resume.
            (Transferring { target }, Event::ConsultEnded) => (
                Transferring {
                    target: target.clone(),
                },
                Action::Nothing,
            ),
            (Placing { .. } | Connected { .. } | Merging { .. }, Event::ConsultEnded) => {
                (Idle, Action::ResumeFirst)
            }
            (s, _) => (s.clone(), Action::Nothing),
        }
    }

    /// Whom the consult is with, if any.
    pub fn target(&self) -> Option<&Person> {
        match self {
            Consult::Idle => None,
            Consult::Placing { target }
            | Consult::Connected { target }
            | Consult::Transferring { target }
            | Consult::Merging { target } => Some(target),
        }
    }

    /// The call window's view: `{state, mri, name}` (state calling,
    /// connected, transferring or merging), or null.
    pub fn view(&self) -> serde_json::Value {
        let state = match self {
            Consult::Idle => return serde_json::Value::Null,
            Consult::Placing { .. } => "calling",
            Consult::Connected { .. } => "connected",
            Consult::Transferring { .. } => "transferring",
            Consult::Merging { .. } => "merging",
        };
        let t = self.target().expect("a consult has a target");
        serde_json::json!({ "state": state, "mri": t.mri, "name": t.name })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn bob() -> Person {
        Person {
            mri: "8:orgid:00000000-0000-0000-0000-00000000000b".into(),
            name: "Bob".into(),
        }
    }

    #[test]
    fn consult_then_transfer() {
        let (s, a) = Consult::Idle.step(Event::Start(bob()));
        assert_eq!(a, Action::HoldAndCall);
        assert_eq!(s.view()["state"], "calling");
        let (s, _) = s.step(Event::Answered);
        assert_eq!(s.view()["state"], "connected");
        let (s, a) = s.step(Event::Transfer);
        assert_eq!(a, Action::SendTransfer);
        // The consult call ends because the transfer replaced it.
        let (s, a) = s.step(Event::ConsultEnded);
        assert_eq!(a, Action::Nothing);
        assert_eq!(s.view()["state"], "transferring");
        let (s, a) = s.step(Event::Done);
        assert_eq!((s, a), (Consult::Idle, Action::Finished));
    }

    #[test]
    fn a_failed_transfer_keeps_the_consult_and_an_ended_one_resumes() {
        let s = Consult::Connected { target: bob() };
        let (s, _) = s.step(Event::Transfer);
        let (s, a) = s.step(Event::Failed);
        assert_eq!(
            (s.clone(), a),
            (Consult::Connected { target: bob() }, Action::Nothing)
        );
        let (s, a) = s.step(Event::ConsultEnded);
        assert_eq!((s, a), (Consult::Idle, Action::ResumeFirst));
        // No answer: back to the held call.
        let (s, a) = Consult::Placing { target: bob() }.step(Event::ConsultEnded);
        assert_eq!((s, a), (Consult::Idle, Action::ResumeFirst));
    }

    #[test]
    fn merge_finishes_in_the_consult_call() {
        let (s, a) = Consult::Connected { target: bob() }.step(Event::Merge);
        assert_eq!(a, Action::SendMerge);
        assert_eq!(s.view()["state"], "merging");
        assert_eq!(s.step(Event::Done), (Consult::Idle, Action::Finished));
        // Transfer and Merge do nothing before the consult call connects.
        let p = Consult::Placing { target: bob() };
        assert_eq!(p.step(Event::Transfer).1, Action::Nothing);
        assert_eq!(p.step(Event::Merge).1, Action::Nothing);
        assert!(Consult::Idle.view().is_null());
    }
}
