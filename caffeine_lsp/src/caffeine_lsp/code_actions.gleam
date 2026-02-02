import caffeine_lsp/diagnostics.{type DiagnosticCode, NoDiagnosticCode}
import gleam/list
import gleam/string

/// A decoded diagnostic from the codeAction request.
pub type ActionDiagnostic {
  ActionDiagnostic(
    line: Int,
    character: Int,
    end_line: Int,
    end_character: Int,
    message: String,
    code: DiagnosticCode,
  )
}

/// A text edit to apply in a code action.
pub type TextEdit {
  TextEdit(
    start_line: Int,
    start_character: Int,
    end_line: Int,
    end_character: Int,
    new_text: String,
  )
}

/// A code action returned to the editor.
pub type CodeAction {
  CodeAction(
    title: String,
    kind: String,
    is_preferred: Bool,
    diagnostic: ActionDiagnostic,
    uri: String,
    edits: List(TextEdit),
  )
}

/// Generate code actions from diagnostics.
pub fn get_code_actions(
  diags: List(ActionDiagnostic),
  uri: String,
) -> List(CodeAction) {
  list.filter_map(diags, fn(d) { diagnostic_to_action(d, uri) })
}

fn diagnostic_to_action(
  diag: ActionDiagnostic,
  uri: String,
) -> Result(CodeAction, Nil) {
  case diag.code {
    diagnostics.QuotedFieldName -> {
      case extract_between(diag.message, "Use '", "' instead") {
        Ok(name) -> Ok(remove_quotes_action(diag, uri, name))
        Error(_) -> Error(Nil)
      }
    }
    NoDiagnosticCode -> Error(Nil)
  }
}

fn remove_quotes_action(
  diag: ActionDiagnostic,
  uri: String,
  name: String,
) -> CodeAction {
  let name_len = string.length(name)
  CodeAction(
    title: "Remove quotes from field name",
    kind: "quickfix",
    is_preferred: True,
    diagnostic: diag,
    uri: uri,
    edits: [
      TextEdit(
        start_line: diag.line,
        start_character: diag.character,
        end_line: diag.line,
        end_character: diag.character + name_len + 2,
        new_text: name,
      ),
    ],
  )
}

fn extract_between(
  s: String,
  prefix: String,
  suffix: String,
) -> Result(String, Nil) {
  case string.split_once(s, prefix) {
    Ok(#(_, after_prefix)) -> {
      case string.split_once(after_prefix, suffix) {
        Ok(#(between, _)) -> Ok(between)
        Error(_) -> Error(Nil)
      }
    }
    Error(_) -> Error(Nil)
  }
}
