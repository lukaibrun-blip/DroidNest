// SPDX-License-Identifier: GPL-2.0-or-later

//! Why the last run stopped.
//!
//! A game runs inside DroidNest's own process, so when it dies it takes the app with it and there is nothing left to ask:
//! what remains is the log the run wrote as it went. This reads that log and says, in one line and one paragraph, what
//! DroidNest can honestly conclude -- a fatal signal, a runtime that refused to start the game, iOS reclaiming the memory,
//! or nothing recorded at all.

use crate::buf::Buf;

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum Kind {
    Unknown,
    Signal(i32),
    StartFailed,
    OutOfMemory,
}

impl Kind {
    /// The number the C boundary carries: 0 unknown, 1 signal (with `signal()`), 2 start failed, 3 out of memory.
    pub fn code(self) -> i32 {
        match self {
            Kind::Unknown => 0,
            Kind::Signal(_) => 1,
            Kind::StartFailed => 2,
            Kind::OutOfMemory => 3,
        }
    }

    pub fn signal(self) -> i32 {
        match self {
            Kind::Signal(n) => n,
            _ => 0,
        }
    }
}

pub struct Crash {
    pub kind: Kind,
    pub title: &'static str,
    pub detail: &'static str,
}

const UNKNOWN: Crash = Crash {
    kind: Kind::Unknown,
    title: "DroidNest closed while the game was running",
    detail: "Nothing was recorded, which usually means iOS ended DroidNest for using too much memory, or DroidNest was \
             closed from the app switcher. The log of that run is still here.",
};

const START_FAILED: Crash = Crash {
    kind: Kind::StartFailed,
    title: "The game could not start",
    detail: "The runtime refused to start it before it drew a frame. The log of that run names the part it could not \
             find.",
};

const OUT_OF_MEMORY: Crash = Crash {
    kind: Kind::OutOfMemory,
    title: "iOS ended DroidNest for using too much memory",
    detail: "The game needed more memory than iOS was willing to give this app. A smaller game, or closing other apps \
             first, is the way round it; nothing in the game is broken.",
};

/// What the last run's log says, and what to tell the person looking at it.
///
/// The order matters: a fatal signal is the hard evidence, and it wins over the guesses. A run that both lost memory and
/// died on SIGSEGV died on the SIGSEGV.
pub fn classify(text: &str) -> Crash {
    if let Some(signal) = fatal_signal(text) {
        let (title, detail) = signal_text(signal);
        return Crash { kind: Kind::Signal(signal), title, detail };
    }
    if text.contains("the game could not be started") || text.contains("native: launch refused") {
        return START_FAILED;
    }
    if text.contains("jetsam") || text.contains("memorystatus") || text.contains("per-process-limit") {
        return OUT_OF_MEMORY;
    }
    UNKNOWN
}

/// The last `*** FATAL SIGNAL n` in a log, which is the run's own last word. The marker is written by HuskLog's signal
/// handler straight to the log file, so it survives the crash that wrote it.
pub fn fatal_signal(text: &str) -> Option<i32> {
    const MARKER: &str = "*** FATAL SIGNAL";
    // The last occurrence, not the first: a log that holds two runs' worth of markers ends on the one that mattered.
    let at = text.rfind(MARKER)? + MARKER.len();
    let rest = text.get(at..)?;
    let mut digits = 0u32;
    for byte in rest.trim_start().bytes() {
        if !byte.is_ascii_digit() {
            break;
        }
        digits = digits.saturating_mul(10).saturating_add((byte - b'0') as u32);
        if digits > i32::MAX as u32 {
            return None;
        }
    }
    if digits == 0 {
        None
    } else {
        Some(digits as i32)
    }
}

fn signal_text(signal: i32) -> (&'static str, &'static str) {
    match signal {
        11 => (
            "The game crashed",
            "It stopped with SIGSEGV, a bad memory access. The log written with this report has the last lines of that \
             run, and the backtrace the crash handler took.",
        ),
        10 => (
            "The game crashed",
            "It stopped with SIGBUS, an access the hardware refused -- usually a library writing where the JIT region \
             does not allow it. The log written with this report has the last lines of that run.",
        ),
        6 => (
            "The game stopped itself",
            "It called abort (SIGABRT): the game or one of its libraries gave up and asked iOS to end the process. The \
             log has the message it printed just before.",
        ),
        4 => (
            "The game hit an instruction this iPhone cannot run",
            "It stopped with SIGILL. The game's code includes something this device's ARM64 CPU does not implement.",
        ),
        8 => ("The game crashed", "It stopped with SIGFPE, an arithmetic fault."),
        12 => (
            "The game used a system call iOS does not allow",
            "It stopped with SIGSYS: it reached for something only Android provides.",
        ),
        5 => (
            "The game crashed",
            "It stopped with SIGTRAP. The log has what it was doing at that moment.",
        ),
        9 => (
            "iOS ended the game",
            "It was ended with SIGKILL, which is what iOS does to an app it has decided to close -- memory pressure is \
             the usual reason.",
        ),
        _ => (
            "The game crashed",
            "It stopped on a fatal signal, recorded in the log written with this report; the last lines of that run are \
             there too.",
        ),
    }
}

/// The whole answer in text, for the report a person can read: "The game crashed\n\nIt stopped with ...".
pub fn describe(crash: &Crash, out: &mut Buf) {
    out.push_str(crash.title);
    out.push_str("\n\n");
    out.push_str(crash.detail);
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::string::String;

    fn render(f: impl Fn(&mut Buf)) -> String {
        let mut storage = [0u8; 1024];
        let written = {
            let mut buf = Buf::new(&mut storage);
            f(&mut buf);
            buf.finish()
        };
        String::from_utf8(storage[..written].to_vec()).unwrap()
    }

    #[test]
    fn a_fatal_signal_is_read_from_the_last_line_that_has_one() {
        assert_eq!(fatal_signal("*** FATAL SIGNAL 11 -- process is dying ***"), Some(11));
        assert_eq!(
            fatal_signal("*** FATAL SIGNAL 6 -- process is dying ***\n...\n*** FATAL SIGNAL 10 -- process is dying ***"),
            Some(10)
        );
        assert_eq!(fatal_signal("nothing here"), None);
        assert_eq!(fatal_signal("*** FATAL SIGNAL without a number"), None);
        assert_eq!(fatal_signal("*** FATAL SIGNAL 0 -- process is dying ***"), None);
    }

    #[test]
    fn segv_says_what_it_means() {
        let c = classify("[1ms][tl] start\n*** FATAL SIGNAL 11 -- process is dying ***\n");
        assert_eq!(c.kind, Kind::Signal(11));
        assert_eq!(c.title, "The game crashed");
        assert!(c.detail.contains("SIGSEGV"));
    }

    #[test]
    fn a_runtime_that_refused_to_start_is_not_a_crash() {
        let c = classify("[tl] the game could not be started: libunity.so missing");
        assert_eq!(c.kind, Kind::StartFailed);
        assert!(c.detail.contains("names the part"));
    }

    #[test]
    fn memory_pressure_is_named_as_such() {
        let c = classify("kernel: memorystatus: killing process 1234 [DroidNest] due to jetsam");
        assert_eq!(c.kind, Kind::OutOfMemory);
        assert!(c.title.contains("memory"));
    }

    #[test]
    fn an_empty_log_is_unknown_and_says_why() {
        let c = classify("");
        assert_eq!(c.kind, Kind::Unknown);
        assert!(c.detail.contains("app switcher"));
    }

    #[test]
    fn a_signal_beats_the_guesses() {
        let c = classify("jetsam\n*** FATAL SIGNAL 11 -- process is dying ***");
        assert_eq!(c.kind, Kind::Signal(11));
    }

    #[test]
    fn every_signal_droidnest_reports_has_a_sentence_of_its_own() {
        for signal in [4, 5, 6, 8, 9, 10, 11, 12] {
            let c = classify(&format!("*** FATAL SIGNAL {signal} -- process is dying ***"));
            assert_eq!(c.kind, Kind::Signal(signal));
            assert!(!c.detail.is_empty());
        }
        // And one nobody listed still gets the honest general sentence rather than a panic.
        let c = classify("*** FATAL SIGNAL 27 -- process is dying ***");
        assert_eq!(c.kind, Kind::Signal(27));
        assert!(c.title == "The game crashed");
    }

    #[test]
    fn kinds_have_the_numbers_the_c_boundary_carries() {
        assert_eq!(Kind::Unknown.code(), 0);
        assert_eq!(Kind::Signal(11).code(), 1);
        assert_eq!(Kind::Signal(11).signal(), 11);
        assert_eq!(Kind::Unknown.signal(), 0);
        assert_eq!(Kind::StartFailed.code(), 2);
        assert_eq!(Kind::OutOfMemory.code(), 3);
    }

    #[test]
    fn a_report_reads_as_a_title_and_an_explanation() {
        let text = render(|buf| describe(&classify("*** FATAL SIGNAL 11 ---"), buf));
        assert!(text.starts_with("The game crashed\n\n"));
        assert!(text.contains("SIGSEGV"));
    }
}
