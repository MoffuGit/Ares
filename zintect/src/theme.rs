use std::str::FromStr;

use serde_json::{Map, Value};
use syntect::highlighting::{
    Color, FontStyle, ScopeSelectors, StyleModifier, Theme, ThemeItem, ThemeSettings,
    UnderlineOption,
};

/// cbindgen:ignore
type JsonObject = Map<String, Value>;

pub(crate) fn parse_theme(json: &str) -> Option<Theme> {
    let root = serde_json::from_str::<Value>(json).ok()?;
    let root_obj = root.as_object()?;
    let colors = root_obj.get("colors").and_then(Value::as_object);

    let highlights_obj = root_obj
        .get("highlights")
        .and_then(Value::as_object)
        .unwrap_or(root_obj);
    let globals = highlights_obj.get("globals").and_then(Value::as_object);
    let rules = highlights_obj.get("rules").and_then(Value::as_array);

    if globals.is_none() && rules.is_none() {
        return None;
    }

    let mut theme = Theme {
        name: root_obj
            .get("name")
            .and_then(Value::as_str)
            .map(str::to_owned),
        ..Theme::default()
    };

    if let Some(globals) = globals {
        apply_globals(&mut theme.settings, globals, colors);
    }

    if let Some(rules) = rules {
        for rule in rules {
            if let Some(item) = parse_rule(rule, colors) {
                theme.scopes.push(item);
            }
        }
    }

    Some(theme)
}

fn apply_globals(settings: &mut ThemeSettings, globals: &JsonObject, colors: Option<&JsonObject>) {
    settings.foreground = resolve_color_key(globals, "foreground", colors);
    settings.background = resolve_color_key(globals, "background", colors);
    settings.caret = resolve_color_key(globals, "caret", colors);
    settings.line_highlight = resolve_color_key(globals, "line_highlight", colors);
    settings.misspelling = resolve_color_key(globals, "misspelling", colors);
    settings.minimap_border = resolve_color_key(globals, "minimap_border", colors);
    settings.accent = resolve_color_key(globals, "accent", colors);
    settings.bracket_contents_foreground =
        resolve_color_key(globals, "bracket_contents_foreground", colors);
    settings.brackets_foreground = resolve_color_key(globals, "brackets_foreground", colors);
    settings.brackets_background = resolve_color_key(globals, "brackets_background", colors);
    settings.tags_foreground = resolve_color_key(globals, "tags_foreground", colors);
    settings.highlight = resolve_color_key(globals, "highlight", colors);
    settings.find_highlight = resolve_color_key(globals, "find_highlight", colors);
    settings.find_highlight_foreground =
        resolve_color_key(globals, "find_highlight_foreground", colors);
    settings.gutter = resolve_color_key(globals, "gutter", colors);
    settings.gutter_foreground = resolve_color_key(globals, "gutter_foreground", colors);
    settings.selection = resolve_color_key(globals, "selection", colors);
    settings.selection_foreground = resolve_color_key(globals, "selection_foreground", colors);
    settings.selection_border = resolve_color_key(globals, "selection_border", colors);
    settings.inactive_selection = resolve_color_key(globals, "inactive_selection", colors);
    settings.inactive_selection_foreground =
        resolve_color_key(globals, "inactive_selection_foreground", colors);
    settings.guide = resolve_color_key(globals, "guide", colors);
    settings.active_guide = resolve_color_key(globals, "active_guide", colors);
    settings.stack_guide = resolve_color_key(globals, "stack_guide", colors);
    settings.shadow = resolve_color_key(globals, "shadow", colors);

    settings.bracket_contents_options = globals
        .get("bracket_contents_options")
        .and_then(Value::as_str)
        .and_then(parse_underline_option);
    settings.brackets_options = globals
        .get("brackets_options")
        .and_then(Value::as_str)
        .and_then(parse_underline_option);
    settings.tags_options = globals
        .get("tags_options")
        .and_then(Value::as_str)
        .and_then(parse_underline_option);
}

fn parse_rule(rule: &Value, colors: Option<&JsonObject>) -> Option<ThemeItem> {
    let rule_obj = rule.as_object()?;
    let selector = rule_obj
        .get("scope")
        .and_then(Value::as_str)
        .filter(|scope| !scope.trim().is_empty())
        .map(str::trim)
        .map(str::to_owned)
        .or_else(|| parse_scopes(rule_obj.get("scopes")?))?;

    let style = StyleModifier {
        foreground: rule_obj
            .get("foreground")
            .and_then(|value| resolve_color_value(value, colors)),
        background: rule_obj
            .get("background")
            .and_then(|value| resolve_color_value(value, colors)),
        font_style: rule_obj
            .get("font_style")
            .and_then(Value::as_str)
            .and_then(parse_font_style),
    };

    if style.foreground.is_none() && style.background.is_none() && style.font_style.is_none() {
        return None;
    }

    let scope = ScopeSelectors::from_str(&selector).ok()?;
    Some(ThemeItem { scope, style })
}

fn parse_scopes(value: &Value) -> Option<String> {
    match value {
        Value::String(scope) if !scope.trim().is_empty() => Some(scope.trim().to_owned()),
        Value::Array(items) => {
            let scopes = items
                .iter()
                .filter_map(Value::as_str)
                .map(str::trim)
                .filter(|scope| !scope.is_empty())
                .collect::<Vec<_>>();
            if scopes.is_empty() {
                None
            } else {
                Some(scopes.join(", "))
            }
        }
        _ => None,
    }
}

fn resolve_color_key(obj: &JsonObject, key: &str, colors: Option<&JsonObject>) -> Option<Color> {
    obj.get(key)
        .and_then(|value| resolve_color_value(value, colors))
}

fn resolve_color_value(value: &Value, colors: Option<&JsonObject>) -> Option<Color> {
    let raw = value.as_str()?;
    resolve_color_str(raw, colors, 0)
}

fn resolve_color_str(value: &str, colors: Option<&JsonObject>, depth: u8) -> Option<Color> {
    if depth > 8 {
        return None;
    }

    if value.starts_with('#') || value.len() == 6 || value.len() == 8 {
        return parse_hex_color(value);
    }

    let alias = colors?.get(value)?.as_str()?;
    resolve_color_str(alias, colors, depth + 1)
}

fn parse_hex_color(value: &str) -> Option<Color> {
    let hex = value.strip_prefix('#').unwrap_or(value);
    match hex.len() {
        6 => Some(Color {
            r: u8::from_str_radix(&hex[0..2], 16).ok()?,
            g: u8::from_str_radix(&hex[2..4], 16).ok()?,
            b: u8::from_str_radix(&hex[4..6], 16).ok()?,
            a: 0xff,
        }),
        8 => Some(Color {
            r: u8::from_str_radix(&hex[0..2], 16).ok()?,
            g: u8::from_str_radix(&hex[2..4], 16).ok()?,
            b: u8::from_str_radix(&hex[4..6], 16).ok()?,
            a: u8::from_str_radix(&hex[6..8], 16).ok()?,
        }),
        _ => None,
    }
}

fn parse_font_style(value: &str) -> Option<FontStyle> {
    let trimmed = value.trim();
    if trimmed.is_empty() || trimmed == "normal" {
        return Some(FontStyle::empty());
    }

    let mut style = FontStyle::empty();
    for token in trimmed.split_whitespace() {
        match token {
            "bold" => style.insert(FontStyle::BOLD),
            "italic" => style.insert(FontStyle::ITALIC),
            "underline" | "stippled_underline" | "squiggly_underline" => {
                style.insert(FontStyle::UNDERLINE)
            }
            _ => {}
        }
    }

    if style.is_empty() { None } else { Some(style) }
}

fn parse_underline_option(value: &str) -> Option<UnderlineOption> {
    if value.contains("squiggly_underline") {
        Some(UnderlineOption::SquigglyUnderline)
    } else if value.contains("stippled_underline") {
        Some(UnderlineOption::StippledUnderline)
    } else if value.contains("underline") {
        Some(UnderlineOption::Underline)
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_highlight_globals_and_rules_from_ares_theme() {
        let json = r##"
        {
          "name": "example",
          "colors": {
            "background": "#101112",
            "foreground": "#f0f1f2",
            "keyword": "#ff6600",
            "comment": "#778899"
          },
          "highlights": {
            "globals": {
              "background": "background",
              "foreground": "foreground",
              "selection": "#223344"
            },
            "rules": [
              {
                "name": "Keywords",
                "scopes": ["keyword", "storage"],
                "foreground": "keyword",
                "font_style": "bold"
              },
              {
                "scope": "comment",
                "foreground": "comment"
              }
            ]
          }
        }
        "##;

        let theme = parse_theme(json).expect("theme should parse");
        assert_eq!(
            theme.settings.background,
            Some(Color {
                r: 0x10,
                g: 0x11,
                b: 0x12,
                a: 0xff
            })
        );
        assert_eq!(
            theme.settings.foreground,
            Some(Color {
                r: 0xf0,
                g: 0xf1,
                b: 0xf2,
                a: 0xff
            })
        );
        assert_eq!(
            theme.settings.selection,
            Some(Color {
                r: 0x22,
                g: 0x33,
                b: 0x44,
                a: 0xff
            })
        );
        assert_eq!(theme.scopes.len(), 2);
        assert_eq!(
            theme.scopes[0].style.foreground,
            Some(Color {
                r: 0xff,
                g: 0x66,
                b: 0x00,
                a: 0xff
            })
        );
        assert_eq!(
            theme.scopes[1].style.foreground,
            Some(Color {
                r: 0x77,
                g: 0x88,
                b: 0x99,
                a: 0xff
            })
        );
    }
}
