// SPDX-License-Identifier: GPL-2.0-or-later

//! A fixed buffer for building a sentence without an allocator.
//!
//! The whole crate is `no_std` and allocation-free: the app crosses the C boundary with a `char *` it owns, and nothing here
//! ever asks iOS for memory. Text that does not fit is cut, never half a character: a truncated message is a nuisance, an
//! invalid UTF-8 sequence handed to Swift is a repair notice.

pub struct Buf<'a> {
    dst: &'a mut [u8],
    len: usize,
}

impl<'a> Buf<'a> {
    pub fn new(dst: &'a mut [u8]) -> Self {
        Buf { dst, len: 0 }
    }

    /// Room left before the NUL that `finish` writes.
    fn room(&self) -> usize {
        self.dst.len().saturating_sub(1).saturating_sub(self.len)
    }

    pub fn push_str(&mut self, text: &str) {
        let room = self.room();
        let mut take = text.len().min(room);
        // Never split a character: a buffer that ends mid-sequence hands Swift invalid UTF-8.
        while take > 0 && !text.is_char_boundary(take) {
            take -= 1;
        }
        if take == 0 {
            return;
        }
        self.dst[self.len..self.len + take].copy_from_slice(&text.as_bytes()[..take]);
        self.len += take;
    }

    pub fn push_u64(&mut self, mut value: u64) {
        if value == 0 {
            self.push_str("0");
            return;
        }
        let mut digits = [0u8; 20];
        let mut at = digits.len();
        while value > 0 {
            at -= 1;
            digits[at] = b'0' + (value % 10) as u8;
            value /= 10;
        }
        // The digits are ASCII, so the slice is always valid UTF-8.
        if let Ok(text) = core::str::from_utf8(&digits[at..]) {
            self.push_str(text);
        }
    }

    pub fn push_i32(&mut self, value: i32) {
        if value < 0 {
            self.push_str("-");
            self.push_u64(value.unsigned_abs() as u64);
        } else {
            self.push_u64(value as u64);
        }
    }

    /// "1.2 GB", "858 MB", "0 bytes" -- the way a person writes a size.
    pub fn push_size(&mut self, bytes: u64) {
        const KB: u64 = 1024;
        const MB: u64 = 1024 * KB;
        const GB: u64 = 1024 * MB;
        const TB: u64 = 1024 * GB;
        if bytes >= TB {
            self.push_scale(bytes, TB);
            self.push_str(" TB");
        } else if bytes >= GB {
            self.push_scale(bytes, GB);
            self.push_str(" GB");
        } else if bytes >= MB {
            // Whole megabytes: "858 MB" is what someone comparing it to their free space wants, not "858.3".
            self.push_u64((bytes + MB / 2) / MB);
            self.push_str(" MB");
        } else if bytes >= KB {
            self.push_u64((bytes + KB / 2) / KB);
            self.push_str(" KB");
        } else {
            self.push_u64(bytes);
            self.push_str(if bytes == 1 { " byte" } else { " bytes" });
        }
    }

    /// One decimal place, from integers only (this crate never touches floating point).
    fn push_scale(&mut self, bytes: u64, unit: u64) {
        let whole = bytes / unit;
        let tenths = ((bytes % unit) * 10 + unit / 2) / unit;
        // Rounding can carry into the whole part: 1.98 GB is 2.0 GB, not 1.10 GB.
        if tenths >= 10 {
            self.push_u64(whole + 1);
            self.push_str(".0");
        } else {
            self.push_u64(whole);
            self.push_str(".");
            self.push_u64(tenths);
        }
    }

    /// NUL-terminate and report how many bytes of text were written (not counting the NUL).
    pub fn finish(self) -> usize {
        let written = self.len;
        if written < self.dst.len() {
            self.dst[written] = 0;
        }
        written
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn render(f: impl Fn(&mut Buf)) -> std::string::String {
        let mut storage = [0u8; 64];
        let written = {
            let mut buf = Buf::new(&mut storage);
            f(&mut buf);
            buf.finish()
        };
        std::string::String::from_utf8(storage[..written].to_vec()).unwrap()
    }

    #[test]
    fn sizes_read_like_a_person_wrote_them() {
        assert_eq!(render(|b| b.push_size(0)), "0 bytes");
        assert_eq!(render(|b| b.push_size(1)), "1 byte");
        assert_eq!(render(|b| b.push_size(1024)), "1 KB");
        assert_eq!(render(|b| b.push_size(1024 * 1024 * 3)), "3 MB");
        assert_eq!(render(|b| b.push_size(1024 * 1024 * 1024 * 2)), "2.0 GB");
    }

    #[test]
    fn rounding_carries_into_the_whole_part() {
        // 1.98 GB has to read 2.0 GB; "1.10 GB" is what the naive version produced.
        let almost_two = 1024 * 1024 * 1024 * 2 - 1024 * 1024 * 20;
        assert_eq!(render(|b| b.push_size(almost_two)), "2.0 GB");
    }

    #[test]
    fn a_buffer_that_is_too_small_is_cut_at_a_character_boundary() {
        // "é" is two bytes; a buffer that ends in the middle of it must drop the whole character.
        let mut storage = [0u8; 4];
        let written = {
            let mut buf = Buf::new(&mut storage);
            buf.push_str("aé");
            buf.finish()
        };
        assert_eq!(written, 3);
        assert_eq!(&storage[..3], "aé".as_bytes());
        assert_eq!(storage[3], 0);
    }

    #[test]
    fn numbers_print_without_a_formatter() {
        assert_eq!(render(|b| b.push_u64(0)), "0");
        assert_eq!(render(|b| b.push_u64(u64::MAX)), "18446744073709551615");
        assert_eq!(render(|b| b.push_i32(-12)), "-12");
    }

    #[test]
    fn nothing_is_written_past_the_end() {
        let mut storage = [7u8; 8];
        {
            let mut buf = Buf::new(&mut storage);
            buf.push_str("aaaaaaaaaaaaaaaaaaaaaaaa");
            buf.finish();
        }
        // Seven characters plus the NUL: the eighth byte is the NUL, and nothing else was touched.
        assert_eq!(&storage[..7], b"aaaaaaa");
        assert_eq!(storage[7], 0);
    }
}
