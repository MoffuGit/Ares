use syntect::{highlighting::ThemeSet, parsing::SyntaxSet};

pub struct Instance {
    syntax_set: SyntaxSet,
    theme_set: ThemeSet,
}

impl Instance {
    pub fn new() -> Instance {
        return Instance {
            syntax_set: SyntaxSet::load_defaults_newlines(),
            theme_set: ThemeSet::load_defaults(),
        };
    }
}
