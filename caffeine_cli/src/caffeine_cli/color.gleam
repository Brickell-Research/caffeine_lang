/// Color utilities with NO_COLOR env var support.
import envoy
import gleam_community/ansi

/// Whether color output is enabled.
pub type ColorMode {
  ColorEnabled
  ColorDisabled
}

/// Detects color mode from environment.
/// Returns ColorDisabled if NO_COLOR env var is set (any value).
pub fn detect_color_mode() -> ColorMode {
  case envoy.get("NO_COLOR") {
    Ok(_) -> ColorDisabled
    Error(_) -> ColorEnabled
  }
}

/// Applies red styling if color is enabled.
pub fn red(text: String, mode: ColorMode) -> String {
  case mode {
    ColorEnabled -> ansi.red(text)
    ColorDisabled -> text
  }
}

/// Applies bold styling if color is enabled.
pub fn bold(text: String, mode: ColorMode) -> String {
  case mode {
    ColorEnabled -> ansi.bold(text)
    ColorDisabled -> text
  }
}

/// Applies cyan styling if color is enabled.
pub fn cyan(text: String, mode: ColorMode) -> String {
  case mode {
    ColorEnabled -> ansi.cyan(text)
    ColorDisabled -> text
  }
}

/// Applies blue styling if color is enabled.
pub fn blue(text: String, mode: ColorMode) -> String {
  case mode {
    ColorEnabled -> ansi.blue(text)
    ColorDisabled -> text
  }
}

/// Applies green styling if color is enabled.
pub fn green(text: String, mode: ColorMode) -> String {
  case mode {
    ColorEnabled -> ansi.green(text)
    ColorDisabled -> text
  }
}

/// Applies dim styling if color is enabled.
pub fn dim(text: String, mode: ColorMode) -> String {
  case mode {
    ColorEnabled -> ansi.dim(text)
    ColorDisabled -> text
  }
}
