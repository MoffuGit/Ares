use std::ffi::c_void;

use syntect::highlighting::{HighlightIterator, HighlightState, Highlighter};
use syntect::parsing::{ParseState, ScopeStack};

use crate::runtime::Runtime;

#[repr(C)]
pub struct Span {
    pub start_byte: u32,
    pub end_byte: u32,
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
    pub font_style: u8,
}

pub type EmitSpanFn = unsafe extern "C" fn(ctx: *mut c_void, line_index: u32, span: Span);

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

    pub fn highlight_line(
        &mut self,
        runtime: &Runtime,
        line: &str,
        line_index: u32,
        ctx: *mut c_void,
        emit: EmitSpanFn,
    ) -> bool {
        let parse_state = match &mut self.parse_state {
            Some(s) => s,
            None => return false,
        };
        let highlight_state = match &mut self.highlight_state {
            Some(s) => s,
            None => return false,
        };

        if let Ok(theme) = runtime.theme.read() {
            let highlighter = Highlighter::new(&*theme);

            let ops = match parse_state.parse_line(line, &runtime.syntax_set) {
                Ok(ops) => ops,
                Err(_) => return false,
            };

            let iter = HighlightIterator::new(highlight_state, &ops, line, &highlighter);

            let mut byte_offset: u32 = 0;
            for (style, text) in iter {
                let len = text.len() as u32;
                if len > 0 {
                    unsafe {
                        emit(
                            ctx,
                            line_index,
                            Span {
                                start_byte: byte_offset,
                                end_byte: byte_offset + len,
                                r: style.foreground.r,
                                g: style.foreground.g,
                                b: style.foreground.b,
                                a: style.foreground.a,
                                font_style: style.font_style.bits(),
                            },
                        );
                    }
                }
                byte_offset += len;
            }

            return true;
        }

        false
    }
}
