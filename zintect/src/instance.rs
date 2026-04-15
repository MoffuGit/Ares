use std::io::{self, IsTerminal, Write};

use syntect::{
    easy::HighlightLines,
    highlighting::Style,
    util::as_24_bit_terminal_escaped,
    util::LinesWithEndings,
};

use crate::runtime::Runtime;

pub struct Instance {}

impl Instance {
    pub fn new() -> Instance {
        Instance {}
    }

    pub fn initial_parse(&self, runtime: &Runtime, buffer: &str, extension: &str) {
        let syntax = runtime
            .syntax_set
            .find_syntax_by_extension(extension)
            .unwrap();
        let mut h = HighlightLines::new(syntax, &runtime.theme_set.themes["base16-ocean.dark"]);
        let stderr = io::stderr();
        let use_colors = stderr.is_terminal();
        let mut stderr = stderr.lock();

        for line in LinesWithEndings::from(buffer) {
            let ranges: Vec<(Style, &str)> = h.highlight_line(line, &runtime.syntax_set).unwrap();

            if use_colors {
                let escaped = as_24_bit_terminal_escaped(&ranges, true);
                stderr.write_all(escaped.as_bytes()).unwrap();
            } else {
                stderr.write_all(line.as_bytes()).unwrap();
            }
        }

        stderr.flush().unwrap();
    }
}
