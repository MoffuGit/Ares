use syntect::{highlighting::ThemeSet, parsing::SyntaxSet};

pub struct Runtime {
    pub syntax_set: SyntaxSet,
    pub theme_set: ThemeSet,
}

impl Runtime {
    pub fn new() -> Runtime {
        Runtime {
            syntax_set: SyntaxSet::load_defaults_newlines(),
            theme_set: ThemeSet::load_defaults(),
        }
    }
}
