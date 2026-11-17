// SPDX-License-Identifier: GPL-2.0-or-later

//! What DroidNest will and will not take in.
//!
//! Husk's importer copies the file first and asks afterwards, so a half-finished download or a web page saved as "game.apk"
//! costs the whole copy and leaves a folder behind. The answer here is decided before a byte is written, from what the file
//! is (its first bytes), how big it is, and what the phone has room for.

use crate::buf::Buf;

/// The extensions DroidNest accepts: an APK, a bundle that is one app's APKs in a zip, and an expansion file (OBB).
pub const ACCEPTED: [&str; 5] = ["apk", "xapk", "apkm", "apks", "obb"];

/// Room left over after the copies, so a phone that is almost full fails here rather than halfway through a copy.
pub const HEADROOM: u64 = 64 * 1024 * 1024;

/// A zip's local-file, empty-archive and spanned signatures. Every APK, and every bundle, begins with one of the three.
const ZIP: [&[u8]; 3] = [b"PK\x03\x04", b"PK\x05\x06", b"PK\x07\x08"];

/// One file, as DroidNest found it before copying it.
pub struct ImportSpec<'a> {
    /// Its name as the picker gave it ("com.game.apk").
    pub name: &'a str,
    /// Its first bytes, or nothing when the file could not be read that far.
    pub head: &'a [u8],
    /// Its size in bytes.
    pub bytes: u64,
    /// What the phone says can still be written, or 0 when that could not be read (which is not a reason to refuse).
    pub free: u64,
    /// Whether a game with the same Android package is already in the library.
    pub installed: bool,
}

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum Verdict {
    /// Go ahead.
    Accept,
    /// Go ahead, but the person should be told this first.
    AcceptWithNote,
    /// Do not copy it.
    Refuse,
}

impl Verdict {
    /// The number the C boundary carries: Swift switches on it.
    pub fn code(self) -> i32 {
        match self {
            Verdict::Accept => 0,
            Verdict::AcceptWithNote => 1,
            Verdict::Refuse => 2,
        }
    }
}

/// The extension as written in the name, without the dot: "" when there is none.
///
/// A dot in a folder name is not an extension, which is why the part before it has to be non-empty and dot-free: "my.folder"
/// has no extension, and neither does "README".
pub fn extension(name: &str) -> &str {
    match name.rsplit_once('.') {
        Some((stem, ext)) if !stem.is_empty() && !stem.contains('/') => ext,
        _ => "",
    }
}

/// Whether the name's extension is `want`, ignoring case: an APK downloaded as "GAME.APK" is an APK.
pub fn extension_is(name: &str, want: &str) -> bool {
    let ext = extension(name);
    ext.len() == want.len() && ext.bytes().zip(want.bytes()).all(|(a, b)| a.eq_ignore_ascii_case(&b))
}

pub fn is_bundle(name: &str) -> bool {
    ["xapk", "apkm", "apks"].iter().any(|ext| extension_is(name, ext))
}

pub fn is_obb(name: &str) -> bool {
    extension_is(name, "obb")
}

pub fn is_apk(name: &str) -> bool {
    extension_is(name, "apk")
}

pub fn is_zip(head: &[u8]) -> bool {
    ZIP.iter().any(|signature| head.starts_with(signature))
}

/// What to do with `spec`, and the sentence that explains it: a refusal, a note, or nothing at all when there is nothing
/// worth saying.
pub fn check(spec: &ImportSpec, out: &mut Buf) -> Verdict {
    if !ACCEPTED.iter().any(|ext| extension_is(spec.name, ext)) {
        out.push_str(spec.name);
        out.push_str(" is not something DroidNest can add. Choose an APK, a bundle of them (.xapk, .apkm, .apks), or the "
                     + "APK's expansion file (.obb).");
        return Verdict::Refuse;
    }
    if spec.bytes == 0 {
        out.push_str(spec.name);
        out.push_str(" is empty (0 bytes), so there is nothing to add. It probably did not finish downloading: download it "
                     + "again and choose the new file.");
        return Verdict::Refuse;
    }
    // An OBB is not a zip, and a head that could not be read is not evidence of anything: only what was read is judged.
    if !is_obb(spec.name) && !spec.head.is_empty() && !is_zip(spec.head) {
        out.push_str(spec.name);
        out.push_str(" is not an APK: an APK is a zip file, and this one does not begin like one. It may have been "
                     + "renamed, or it may be a web page saved from a download that failed.");
        return Verdict::Refuse;
    }
    if spec.free > 0 && spec.bytes.saturating_add(HEADROOM) > spec.free {
        out.push_str("There is not enough room for this: it needs about ");
        out.push_size(spec.bytes);
        out.push_str(", and this iPhone has ");
        out.push_size(spec.free);
        out.push_str(" free. Remove something, or free up space, and try again.");
        return Verdict::Refuse;
    }
    if spec.installed {
        out.push_str(spec.name);
        out.push_str(" is already in DroidNest (the same Android package). This one is added beside it as a separate copy, "
                     + "so the game you already have is never replaced or deleted.");
        return Verdict::AcceptWithNote;
    }
    Verdict::Accept
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::string::String;

    const APK_HEAD: &[u8] = b"PK\x03\x04\x14\x00";
    const BUNDLE_HEAD: &[u8] = b"PK\x03\x04\x14\x00\x08\x08";
    const FREE: u64 = 8_000_000_000;

    /// Enough for any sentence this module writes, so the truncation tests are the only ones that ever fill it.
    const CAP: usize = 1024;

    fn render(spec: &ImportSpec) -> (Verdict, String) {
        let mut storage = [0u8; CAP];
        let verdict;
        let text = {
            let mut buf = Buf::new(&mut storage);
            verdict = check(spec, &mut buf);
            let written = buf.finish();
            String::from_utf8(storage[..written].to_vec()).unwrap()
        };
        (verdict, text)
    }

    fn spec<'a>(name: &'a str, head: &'a [u8], bytes: u64) -> ImportSpec<'a> {
        ImportSpec { name, head, bytes, free: FREE, installed: false }
    }

    #[test]
    fn extensions_are_read_ignoring_case() {
        assert_eq!(extension("Game.APK"), "APK");
        assert!(extension_is("Game.APK", "apk"));
        assert!(extension_is("bundle.XAPK", "xapk"));
        assert_eq!(extension("README"), "");
        assert!(!ACCEPTED.iter().any(|ext| extension_is("README", ext)));
        assert_eq!(extension("game.apk.part"), "part");
        // A dot in a folder name is not the file's extension.
        assert_eq!(extension("my.folder/game"), "game");
        assert_eq!(extension("my.folder/game"), "game");
    }

    #[test]
    fn bundles_and_obb_files_are_known() {
        assert!(is_bundle("a.xapk") && is_bundle("a.apkm") && is_bundle("a.apks"));
        assert!(!is_bundle("a.apk"));
        assert!(is_obb("main.1.com.game.obb"));
        assert!(is_apk("GAME.APK"));
        assert!(!is_apk("game.apk.part"));
    }

    #[test]
    fn a_zip_is_recognised_by_any_of_its_signatures() {
        assert!(is_zip(APK_HEAD));
        assert!(is_zip(b"PK\x05\x06\x00\x00"));
        assert!(is_zip(b"PK\x07\x08"));
        assert!(!is_zip(b"<html>"));
        assert!(!is_zip(b""));
    }

    #[test]
    fn an_apk_is_taken_silently() {
        let (verdict, text) = render(&spec("game.apk", APK_HEAD, 200_000_000));
        assert_eq!(verdict, Verdict::Accept);
        assert_eq!(text, "", "a plain APK needs no sentence");
        assert_eq!(render(&spec("bundle.xapk", BUNDLE_HEAD, 900_000_000)).0, Verdict::Accept);
    }

    #[test]
    fn anything_else_is_refused_by_name_and_says_what_is_taken() {
        let (verdict, why) = render(&spec("notes.txt", b"hello", 10));
        assert_eq!(verdict, Verdict::Refuse);
        assert!(why.contains("notes.txt"));
        assert!(why.contains(".apk"));
        assert!(why.contains(".obb"));
    }

    #[test]
    fn an_empty_file_is_refused_before_the_copy() {
        let (verdict, why) = render(&spec("game.apk", &[], 0));
        assert_eq!(verdict, Verdict::Refuse);
        assert!(why.contains("0 bytes"));
    }

    #[test]
    fn a_file_that_is_not_a_zip_is_refused() {
        // What a failed download actually leaves: the web page, saved under the APK's name.
        let (verdict, why) = render(&spec("game.apk", b"<!DOCTYPE html>", 4_000));
        assert_eq!(verdict, Verdict::Refuse);
        assert!(why.contains("not an APK"));
    }

    #[test]
    fn a_head_that_could_not_be_read_is_not_a_refusal() {
        // The picker handed over a file the app could not open yet (an iCloud file still downloading): the copy itself
        // reports the real failure, and guessing here would refuse a perfectly good APK.
        assert_eq!(render(&spec("game.apk", &[], 200_000_000)).0, Verdict::Accept);
    }

    #[test]
    fn an_obb_needs_no_zip_header() {
        assert_eq!(render(&spec("main.1.com.game.obb", b"\x00\x01\x02", 400_000_000)).0, Verdict::Accept);
    }

    #[test]
    fn a_phone_with_no_room_says_how_much_is_needed_and_how_much_there_is() {
        let s = ImportSpec { name: "game.apk", head: APK_HEAD, bytes: 900_000_000, free: 950_000_000, installed: false };
        let (verdict, why) = render(&s);
        assert_eq!(verdict, Verdict::Refuse);
        assert!(why.contains("not enough room"), "{why}");
        // 900 000 000 bytes reads as 858 MB; 950 000 000 as 906 MB.
        assert!(why.contains("858 MB"), "{why}");
        assert!(why.contains("906 MB"), "{why}");
    }

    #[test]
    fn exactly_enough_room_with_the_headroom_kept_is_accepted() {
        // The boundary the first version of DroidNest's own check got wrong: 800 MB of files with 100 MB of headroom
        // fits in 900 MB exactly, and refusing it would refuse a copy that has all the room it needs.
        let s = ImportSpec {
            name: "game.apk",
            head: APK_HEAD,
            bytes: 800_000_000,
            free: 800_000_000 + HEADROOM,
            installed: false,
        };
        assert_eq!(render(&s).0, Verdict::Accept);
    }

    #[test]
    fn free_space_that_could_not_be_read_is_not_a_refusal() {
        let s = ImportSpec { name: "game.apk", head: APK_HEAD, bytes: 4_000_000_000, free: 0, installed: false };
        assert_eq!(render(&s).0, Verdict::Accept);
    }

    #[test]
    fn a_game_already_here_is_taken_with_a_note_rather_than_replaced() {
        let s = ImportSpec { name: "game.apk", head: APK_HEAD, bytes: 200_000_000, free: FREE, installed: true };
        let (verdict, note) = render(&s);
        assert_eq!(verdict, Verdict::AcceptWithNote);
        assert!(note.contains("already in DroidNest"), "{note}");
        assert!(note.contains("never replaced"), "{note}");
    }

    #[test]
    fn verdicts_have_the_numbers_the_c_boundary_carries() {
        assert_eq!(Verdict::Accept.code(), 0);
        assert_eq!(Verdict::AcceptWithNote.code(), 1);
        assert_eq!(Verdict::Refuse.code(), 2);
    }

    #[test]
    fn a_refusal_never_takes_more_than_a_buffer_holds() {
        // A name long enough to fill the sentence's buffer: the message is cut, never a crash and never invalid UTF-8.
        let long = "é".repeat(2000);
        let (verdict, why) = render(&spec(&long, b"nope", 1));
        assert_eq!(verdict, Verdict::Refuse);
        assert!(why.len() <= CAP - 1, "the buffer was overflowed: {} bytes", why.len());
        assert!(why.chars().all(|c| c == 'é' || c.is_ascii()));
    }
}
