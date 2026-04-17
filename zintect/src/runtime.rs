use std::sync::RwLock;

use syntect::highlighting::{Theme, ThemeSet};
use syntect::parsing::SyntaxSet;

use crate::theme::parse_theme;

pub struct Runtime {
    pub syntax_set: SyntaxSet,
    pub theme: RwLock<Theme>,
}

impl Runtime {
    pub fn new() -> Runtime {
        let theme_set = ThemeSet::load_defaults();
        let theme = theme_set
            .themes
            .get("base16-ocean.dark")
            .cloned()
            .or_else(|| theme_set.themes.values().next().cloned())
            .unwrap_or_default();

        Runtime {
            syntax_set: SyntaxSet::load_defaults_newlines(),
            theme: RwLock::new(theme),
        }
    }

    pub fn set_theme_from_json(&mut self, json: &str) -> bool {
        match parse_theme(json) {
            Some(new) => {
                if let Ok(mut theme) = self.theme.write() {
                    *theme = new;
                }
                true
            }
            None => false,
        }
    }
}
