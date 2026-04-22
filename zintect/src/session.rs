use std::ffi::c_void;
use std::ptr;

use syntect::highlighting::{HighlightIterator, HighlightState, Highlighter};
use syntect::parsing::{ParseState, ScopeStack};

use crate::runtime::Runtime;

#[repr(C)]
pub struct FffResult {
    /// Whether the operation succeeded.
    pub success: bool,
    /// Opaque pointer payload. May be null.
    pub handle: *mut c_void,
}

impl FffResult {
    pub fn err() -> Self {
        Self {
            success: false,
            handle: ptr::null_mut(),
        }
    }

    pub fn ok(handle: *mut c_void) -> Self {
        Self {
            success: true,
            handle,
        }
    }
}

#[repr(C)]
pub struct FffHighlightResult {
    pub items: *mut FffSpan,
    pub count: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct FffSpan {
    /// Start offset as a Unicode scalar-value index within the UTF-8 input line.
    pub start: u32,
    /// End offset as a Unicode scalar-value index within the UTF-8 input line.
    pub end: u32,
    pub color: [u8; 4],
    pub font_style: u8,
}

impl FffHighlightResult {
    pub fn from_highlight_iter(iter: HighlightIterator) -> *mut Self {
        let mut offset: u32 = 0;
        let items: Vec<FffSpan> = iter
            .filter_map(|(style, text)| {
                let len = text.chars().count() as u32;
                if len == 0 {
                    return None;
                }

                let start = offset;
                offset += len;

                let fg = style.foreground;
                let color = [fg.r, fg.g, fg.b, fg.a];

                Some(FffSpan {
                    start,
                    end: start + len,
                    color,
                    font_style: style.font_style.bits(),
                })
            })
            .collect();

        let count = items.len() as u32;
        let (items_ptr, _) = vec_to_raw(items);

        Box::into_raw(Box::new(FffHighlightResult {
            items: items_ptr,
            count,
        }))
    }
}

pub struct Session {
    extension: Option<String>,
    parse_state: Option<ParseState>,
    highlight_state: Option<HighlightState>,
}

impl Session {
    pub fn new() -> Self {
        Session {
            extension: None,
            parse_state: None,
            highlight_state: None,
        }
    }

    pub fn set_syntax_by_ext(&mut self, runtime: &Runtime, ext: &str) -> bool {
        self.configure(runtime, ext)
    }

    pub fn reset(&mut self, runtime: &Runtime) -> bool {
        let ext = match &self.extension {
            Some(e) => e.clone(),
            None => return false,
        };
        self.configure(runtime, &ext)
    }

    fn configure(&mut self, runtime: &Runtime, ext: &str) -> bool {
        let syntax = match runtime.syntax_set.find_syntax_by_extension(ext) {
            Some(s) => s,
            None => return false,
        };

        if let Ok(theme) = runtime.theme.read() {
            let highlighter = Highlighter::new(&*theme);

            self.extension = Some(ext.to_string());
            self.parse_state = Some(ParseState::new(syntax));
            self.highlight_state = Some(HighlightState::new(&highlighter, ScopeStack::new()));

            return true;
        }

        false
    }

    pub fn highlight_line(&mut self, runtime: &Runtime, line: &str) -> FffResult {
        let parse_state = match &mut self.parse_state {
            Some(s) => s,
            None => return FffResult::err(),
        };
        let highlight_state = match &mut self.highlight_state {
            Some(s) => s,
            None => return FffResult::err(),
        };

        if let Ok(theme) = runtime.theme.read() {
            let highlighter = Highlighter::new(&*theme);

            let ops = match parse_state.parse_line(line, &runtime.syntax_set) {
                Ok(ops) => ops,
                Err(_) => return FffResult::err(),
            };

            let iter = HighlightIterator::new(highlight_state, &ops, line, &highlighter);

            let res = FffHighlightResult::from_highlight_iter(iter);

            return FffResult::ok(res as *mut c_void);
        }

        FffResult::err()
    }
}

/// Convert a `Vec<T>` into a raw pointer + count, leaking the memory.
fn vec_to_raw<T>(v: Vec<T>) -> (*mut T, u32) {
    if v.is_empty() {
        return (ptr::null_mut(), 0);
    }
    let count = v.len() as u32;
    let mut boxed = v.into_boxed_slice();
    let p = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    (p, count)
}

#[cfg(test)]
mod tests {
    use std::slice;

    use super::*;

    fn collect_spans(result: FffResult) -> Vec<FffSpan> {
        assert!(result.success);

        let handle = result.handle as *mut FffHighlightResult;
        assert!(!handle.is_null());

        unsafe {
            let highlight_result = Box::from_raw(handle);
            let spans = if highlight_result.count == 0 || highlight_result.items.is_null() {
                Vec::new()
            } else {
                slice::from_raw_parts(highlight_result.items, highlight_result.count as usize)
                    .to_vec()
            };

            if !highlight_result.items.is_null() {
                let count = highlight_result.count as usize;
                _ = Vec::from_raw_parts(highlight_result.items, count, count);
            }

            spans
        }
    }

    #[test]
    fn highlight_spans_use_unicode_scalar_offsets() {
        let runtime = Runtime::new();
        let mut session = Session::new();

        assert!(session.set_syntax_by_ext(&runtime, "rs"));

        let line = "let café = \"π😊\";\n";
        let spans = collect_spans(session.highlight_line(&runtime, line));

        assert!(!spans.is_empty());

        let expected_len = line.chars().count() as u32;
        assert!(expected_len < line.len() as u32);
        assert_eq!(spans.first().unwrap().start, 0);
        assert_eq!(spans.last().unwrap().end, expected_len);

        for span in &spans {
            assert!(span.start < span.end);
            assert!(span.end <= expected_len);
        }

        for pair in spans.windows(2) {
            assert_eq!(pair[0].end, pair[1].start);
        }
    }
}
