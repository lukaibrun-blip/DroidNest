// SPDX-License-Identifier: GPL-2.0-or-later

//! DroidNest's own decisions, in Rust, behind a C interface Swift can call.
//!
//! Two things live here, and nothing else:
//!
//! - [`import`]: whether a file the picker handed over is something DroidNest should copy, decided **before** the copy
//!   (Husk's importer copies first and asks afterwards, which is how a half-downloaded APK becomes a half-made folder).
//! - [`crash`]: what the last run's log says about why it stopped -- a fatal signal, a runtime that refused to start the
//!   game, iOS reclaiming the memory, or nothing recorded.
//!
//! The crate is `no_std` and allocation-free: it is linked into an app that already carries one Rust staticlib
//! (`src/rppairing-ios`, for built-in StikJIT's pairing), and a second copy of std in the same binary is a linker problem
//! nobody needs for a pair of pure functions. Text crosses the boundary in a `char *` the caller owns.
//!
//! Every function here is safe to call with anything: a null pointer, a length that does not match, a buffer of zero
//! bytes. The app cannot be taken down by a log file.

#![cfg_attr(not(test), no_std)]

pub mod buf;
pub mod crash;
pub mod import;

use core::slice;

/// The API's own version, so a build can say which core it was linked against. Bump it whenever the C interface below
/// changes shape; `DroidNestCore.h` and this number are the same promise.
const VERSION: &[u8] = b"droidnest-core 1\0";

/// The bytes for `droidnest_core_version`. Static, NUL-terminated, never freed.
#[no_mangle]
pub extern "C" fn droidnest_core_version() -> *const u8 {
    VERSION.as_ptr()
}

/// A borrowed `&str` from a C string and length, or "" when the pointer is null or the bytes are not UTF-8.
///
/// Invalid UTF-8 is not an error to report back: a file name the app cannot even read as text is a file DroidNest will
/// refuse for its extension, which is the honest answer.
unsafe fn str_from(ptr: *const u8, len: usize) -> &'static str {
    if ptr.is_null() || len == 0 {
        return "";
    }
    let bytes = slice::from_raw_parts(ptr, len);
    core::str::from_utf8(bytes).unwrap_or("")
}

unsafe fn bytes_from<'a>(ptr: *const u8, len: usize) -> &'a [u8] {
    if ptr.is_null() || len == 0 {
        return &[];
    }
    slice::from_raw_parts(ptr, len)
}

/// Writes `len` bytes of `text` at `out` and NUL-terminates it, if there is room. Returns the bytes written.
fn write_out(text: &[u8], out: *mut u8, cap: usize) -> usize {
    if out.is_null() || cap == 0 {
        return 0;
    }
    let n = text.len().min(cap - 1);
    unsafe {
        core::ptr::copy_nonoverlapping(text.as_ptr(), out, n);
        *out.add(n) = 0;
    }
    n
}

// MARK: - importing

/// Whether a file should be copied in: 0 accept, 1 accept with a note, 2 refuse.
///
/// `name`/`name_len` are the file's name as the picker gave it. `head`/`head_len` are its first bytes (a null pointer or a
/// zero length means "could not be read", which is not a refusal). `free_bytes` is what the phone says can still be
/// written, or 0 when that could not be read. `installed` is 1 when a game with the same Android package is already in the
/// library.
///
/// `out`/`out_cap` receive the sentence to show, on 1 and 2 alike (empty on 0). The return value is that sentence's
/// length in bytes, not counting the NUL.
#[no_mangle]
pub unsafe extern "C" fn droidnest_import_check(
    name: *const u8,
    name_len: usize,
    head: *const u8,
    head_len: usize,
    bytes: u64,
    free_bytes: u64,
    installed: i32,
    out: *mut u8,
    out_cap: usize,
) -> i32 {
    let spec = import::ImportSpec {
        name: str_from(name, name_len),
        head: bytes_from(head, head_len),
        bytes,
        free: free_bytes,
        installed: installed != 0,
    };

    // The sentence is built twice at worst: once to learn its length, once into the caller's buffer. It is at most a few
    // hundred bytes, and the caller's buffer is the one the app is going to show.
    let mut scratch = [0u8; 1024];
    let mut built = buf::Buf::new(&mut scratch);
    let verdict = import::check(&spec, &mut built);
    let written = built.finish();

    write_out(&scratch[..written], out, out_cap);
    verdict.code()
}

// MARK: - why the last run stopped

/// 0 unknown, 1 a fatal signal, 2 the game could not start, 3 iOS ended DroidNest for memory.
#[no_mangle]
pub unsafe extern "C" fn droidnest_crash_code(log: *const u8, len: usize) -> i32 {
    let text = str_from(log, len);
    crash::classify(text).kind.code()
}

/// The signal behind `droidnest_crash_code` == 1, or 0 when there was none.
#[no_mangle]
pub unsafe extern "C" fn droidnest_crash_signal(log: *const u8, len: usize) -> i32 {
    let text = str_from(log, len);
    crash::classify(text).kind.signal()
}

/// The whole explanation as one piece of text: a title, a blank line, then the detail. Written into `out`/`out_cap`; the
/// return value is its length in bytes, not counting the NUL.
#[no_mangle]
pub unsafe extern "C" fn droidnest_crash_describe(
    log: *const u8,
    len: usize,
    out: *mut u8,
    out_cap: usize,
) -> i32 {
    let text = str_from(log, len);
    let classified = crash::classify(text);
    let mut scratch = [0u8; 1024];
    let mut built = buf::Buf::new(&mut scratch);
    crash::describe(&classified, &mut built);
    let written = built.finish();
    write_out(&scratch[..written], out, out_cap) as i32
}

// MARK: - the panic handler the staticlib needs

// `no_std` has to say what a panic does. On iOS the answer is abort(3): there is no unwinding out of a Rust frame and into
// Swift, and a panic in either of the two modules above would be a bug in a pure function over a byte slice. Nothing here
// is reachable from a bad log file -- every slice is length-checked and every character boundary is respected -- and the
// app has its own crash handler writing the log if it ever is.
#[cfg(not(test))]
extern "C" {
    fn abort() -> !;
}

#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    unsafe { abort() }
}
