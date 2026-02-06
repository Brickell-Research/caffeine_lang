/// AST-based pretty-printer for Caffeine source files.
/// Parses source to AST then emits canonical formatting.
import caffeine_lang/frontend/ast.{
  type BlueprintItem, type BlueprintsBlock, type BlueprintsFile, type Comment,
  type ExpectItem, type ExpectsBlock, type ExpectsFile, type Extendable,
  type Field, type Literal, type Struct, type TypeAlias, ExtendableProvides,
  ExtendableRequires, LiteralFalse, LiteralFloat, LiteralInteger, LiteralList,
  LiteralString, LiteralStruct, LiteralTrue, LiteralValue, Struct, TypeValue,
}
import caffeine_lang/frontend/parser
import caffeine_lang/frontend/token
import caffeine_lang/frontend/tokenizer
import caffeine_lang/types.{
  type CollectionTypes, type ModifierTypes, type ParsedType, type PrimitiveTypes,
  type RefinementTypes, Boolean, Defaulted, Dict, Float, InclusiveRange, Integer,
  List as ListType, NumericType, OneOf, Optional, ParsedCollection,
  ParsedModifier, ParsedPrimitive, ParsedRecord, ParsedRefinement,
  ParsedTypeAliasRef, SemanticType, String as StringType, URL,
}
import gleam/bool
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/set
import gleam/string

type FieldContext {
  TypeFields
  LiteralFields
}

/// Format a Caffeine source file. Auto-detects whether it's a blueprints or expectations file.
pub fn format(source: String) -> Result(String, String) {
  use tokens <- result.try(
    tokenizer.tokenize(source)
    |> result.map_error(fn(_) { "Tokenization error" }),
  )

  let first_keyword =
    tokens
    |> list.find(fn(ptok) {
      case ptok {
        token.PositionedToken(token.KeywordBlueprints, _, _) -> True
        token.PositionedToken(token.KeywordExpectations, _, _) -> True
        _ -> False
      }
    })

  case first_keyword {
    Ok(token.PositionedToken(token.KeywordBlueprints, _, _)) -> {
      use parsed <- result.try(
        parser.parse_blueprints_file(source)
        |> result.map_error(fn(err) { "Parse error: " <> string.inspect(err) }),
      )
      Ok(format_blueprints_file(parsed))
    }
    Ok(token.PositionedToken(token.KeywordExpectations, _, _)) -> {
      use parsed <- result.try(
        parser.parse_expects_file(source)
        |> result.map_error(fn(err) { "Parse error: " <> string.inspect(err) }),
      )
      Ok(format_expects_file(parsed))
    }
    _ ->
      Error(
        "Unable to detect file type: no Blueprints or Expectations keyword found",
      )
  }
}

fn format_blueprints_file(file: BlueprintsFile) -> String {
  let sections: List(String) = []

  let sections = case file.type_aliases {
    [] -> sections
    aliases ->
      list.append(sections, [
        list.map(aliases, format_type_alias) |> string.join("\n"),
      ])
  }

  let sections = case file.extendables {
    [] -> sections
    extendables ->
      list.append(sections, [
        list.map(extendables, format_extendable) |> string.join("\n"),
      ])
  }

  let sections = case file.blocks {
    [] -> sections
    blocks -> list.append(sections, list.map(blocks, format_blueprints_block))
  }

  let trailing = format_comments(file.trailing_comments, "")

  string.join(sections, "\n\n") <> "\n" <> trailing
}

fn format_expects_file(file: ExpectsFile) -> String {
  let sections: List(String) = []

  let sections = case file.extendables {
    [] -> sections
    extendables ->
      list.append(sections, [
        list.map(extendables, format_extendable) |> string.join("\n"),
      ])
  }

  let sections = case file.blocks {
    [] -> sections
    blocks -> list.append(sections, list.map(blocks, format_expects_block))
  }

  let trailing = format_comments(file.trailing_comments, "")

  string.join(sections, "\n\n") <> "\n" <> trailing
}

fn format_comments(comments: List(Comment), indent: String) -> String {
  case comments {
    [] -> ""
    _ ->
      comments
      |> list.map(fn(c) {
        case c {
          ast.LineComment(text) -> indent <> "#" <> text <> "\n"
          ast.SectionComment(text) -> indent <> "##" <> text <> "\n"
        }
      })
      |> string.concat
  }
}

fn format_type_alias(alias: TypeAlias) -> String {
  format_comments(alias.leading_comments, "")
  <> alias.name
  <> " (Type): "
  <> format_type(alias.type_)
}

fn format_extendable(ext: Extendable) -> String {
  let kind_str = case ext.kind {
    ExtendableRequires -> "Requires"
    ExtendableProvides -> "Provides"
  }
  let context = case ext.kind {
    ExtendableRequires -> TypeFields
    ExtendableProvides -> LiteralFields
  }
  format_comments(ext.leading_comments, "")
  <> ext.name
  <> " ("
  <> kind_str
  <> "): "
  <> format_struct(ext.body, 0, context)
}

fn format_blueprints_block(block: BlueprintsBlock) -> String {
  let comments = format_comments(block.leading_comments, "")
  let header =
    "Blueprints for "
    <> block.artifacts
    |> list.map(fn(a) { "\"" <> a <> "\"" })
    |> string.join(" + ")

  let items =
    block.items
    |> list.map(format_blueprint_item)
    |> string.join("\n\n")

  comments <> header <> "\n" <> items
}

fn format_expects_block(block: ExpectsBlock) -> String {
  let comments = format_comments(block.leading_comments, "")
  let header = "Expectations for \"" <> block.blueprint <> "\""

  let items =
    block.items
    |> list.map(format_expect_item)
    |> string.join("\n\n")

  comments <> header <> "\n" <> items
}

fn format_blueprint_item(item: BlueprintItem) -> String {
  let comments = format_comments(item.leading_comments, "  ")
  let name_line =
    "  * \"" <> item.name <> "\"" <> format_extends(item.extends) <> ":"

  let requires = "    Requires " <> format_struct(item.requires, 4, TypeFields)
  let provides =
    "    Provides " <> format_struct(item.provides, 4, LiteralFields)

  comments <> name_line <> "\n" <> requires <> "\n" <> provides
}

fn format_expect_item(item: ExpectItem) -> String {
  let comments = format_comments(item.leading_comments, "  ")
  let name_line =
    "  * \"" <> item.name <> "\"" <> format_extends(item.extends) <> ":"

  let provides =
    "    Provides " <> format_struct(item.provides, 4, LiteralFields)

  comments <> name_line <> "\n" <> provides
}

fn format_extends(extends: List(String)) -> String {
  case extends {
    [] -> ""
    names -> " extends [" <> string.join(names, ", ") <> "]"
  }
}

fn format_struct(s: Struct, indent: Int, context: FieldContext) -> String {
  let has_field_comments =
    list.any(s.fields, fn(f) { f.leading_comments != [] })
  let has_trailing_comments = s.trailing_comments != []
  let has_any_comments = has_field_comments || has_trailing_comments
  case s.fields {
    [] ->
      case has_trailing_comments {
        True ->
          "{\n"
          <> format_comments(
            s.trailing_comments,
            string.repeat(" ", indent + 2),
          )
          <> string.repeat(" ", indent)
          <> "}"
        False -> "{ }"
      }
    fields -> {
      // Force multiline if any comments are present
      use <- bool.guard(
        has_any_comments,
        format_struct_multiline(s, indent + 2, context),
      )
      let inline = format_struct_inline(fields, context)
      let prefix_len = indent + 10
      // Prefer inline when it fits within 80 columns
      use <- bool.guard(string.length(inline) + prefix_len < 80, inline)
      format_struct_multiline(s, indent + 2, context)
    }
  }
}

fn format_struct_inline(fields: List(Field), context: FieldContext) -> String {
  let field_strs =
    fields
    |> list.map(fn(f) { format_field(f, 0, context) })
  "{ " <> string.join(field_strs, ", ") <> " }"
}

fn format_struct_multiline(
  s: Struct,
  indent: Int,
  context: FieldContext,
) -> String {
  let indent_str = string.repeat(" ", indent)
  let field_lines =
    s.fields
    |> list.map(fn(f) {
      let comments = format_comments(f.leading_comments, indent_str)
      comments <> indent_str <> format_field(f, indent, context)
    })

  let trailing = format_comments(s.trailing_comments, indent_str)

  "{\n"
  <> string.join(field_lines, ",\n")
  <> "\n"
  <> trailing
  <> string.repeat(" ", indent - 2)
  <> "}"
}

fn format_field(f: Field, indent: Int, context: FieldContext) -> String {
  case f.value {
    TypeValue(t) -> f.name <> ": " <> format_type(t)
    LiteralValue(l) -> f.name <> ": " <> format_literal(l, indent, context)
  }
}

fn format_type(t: ParsedType) -> String {
  case t {
    ParsedPrimitive(p) -> format_primitive_type(p)
    ParsedCollection(c) -> format_collection_type(c)
    ParsedModifier(m) -> format_modifier_type(m)
    ParsedRefinement(r) -> format_refinement_type(r)
    ParsedTypeAliasRef(name) -> name
    ParsedRecord(fields) -> format_record_type(fields)
  }
}

fn format_primitive_type(p: PrimitiveTypes) -> String {
  case p {
    Boolean -> "Boolean"
    StringType -> "String"
    NumericType(n) ->
      case n {
        Integer -> "Integer"
        Float -> "Float"
      }
    SemanticType(s) ->
      case s {
        URL -> "URL"
      }
  }
}

fn format_collection_type(c: CollectionTypes(ParsedType)) -> String {
  case c {
    ListType(inner) -> "List(" <> format_type(inner) <> ")"
    Dict(key, value) ->
      "Dict(" <> format_type(key) <> ", " <> format_type(value) <> ")"
  }
}

fn format_record_type(fields: dict.Dict(String, ParsedType)) -> String {
  let field_strs =
    fields
    |> dict.to_list
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    |> list.map(fn(pair) { pair.0 <> ": " <> format_type(pair.1) })
  "{ " <> string.join(field_strs, ", ") <> " }"
}

fn format_modifier_type(m: ModifierTypes(ParsedType)) -> String {
  case m {
    Optional(inner) -> "Optional(" <> format_type(inner) <> ")"
    Defaulted(inner, default_val) ->
      "Defaulted("
      <> format_type(inner)
      <> ", "
      <> quote_if_string_type(inner, default_val)
      <> ")"
  }
}

fn quote_if_string_type(inner: ParsedType, val: String) -> String {
  let quote = case inner {
    // Type aliases can't be resolved at format time, so check whether the
    // value itself looks like a non-numeric, non-boolean literal.
    ParsedTypeAliasRef(_) -> value_needs_quoting(val)
    _ -> needs_string_quoting(inner)
  }
  use <- bool.guard(quote, "\"" <> val <> "\"")
  val
}

fn needs_string_quoting(t: ParsedType) -> Bool {
  case t {
    ParsedPrimitive(StringType) -> True
    ParsedPrimitive(SemanticType(_)) -> True
    ParsedRefinement(OneOf(inner, _)) -> needs_string_quoting(inner)
    ParsedRefinement(InclusiveRange(inner, _, _)) -> needs_string_quoting(inner)
    ParsedRecord(_) -> False
    _ -> False
  }
}

/// A default value needs quoting if it isn't a number or boolean literal.
fn value_needs_quoting(val: String) -> Bool {
  case val {
    "True" | "False" -> False
    _ ->
      case int.parse(val) {
        Ok(_) -> False
        Error(_) ->
          case float.parse(val) {
            Ok(_) -> False
            Error(_) -> True
          }
      }
  }
}

fn format_refinement_type(r: RefinementTypes(ParsedType)) -> String {
  case r {
    OneOf(inner, values) -> {
      let quote = needs_string_quoting(inner)
      let sorted_vals =
        values
        |> set.to_list
        |> list.sort(string.compare)
        |> list.map(fn(v) {
          use <- bool.guard(quote, "\"" <> v <> "\"")
          v
        })
        |> string.join(", ")
      format_type(inner) <> " { x | x in { " <> sorted_vals <> " } }"
    }
    InclusiveRange(inner, low, high) ->
      format_type(inner) <> " { x | x in ( " <> low <> ".." <> high <> " ) }"
  }
}

fn format_literal(l: Literal, indent: Int, context: FieldContext) -> String {
  case l {
    LiteralString(s) -> "\"" <> s <> "\""
    LiteralInteger(i) -> int.to_string(i)
    LiteralFloat(f) -> float.to_string(f)
    LiteralTrue -> "true"
    LiteralFalse -> "false"
    LiteralList(elements) -> format_literal_list(elements, indent, context)
    LiteralStruct(fields, trailing_comments) ->
      format_struct(
        Struct(fields, trailing_comments: trailing_comments),
        indent,
        context,
      )
  }
}

fn format_literal_list(
  elements: List(Literal),
  indent: Int,
  context: FieldContext,
) -> String {
  let element_strs =
    elements
    |> list.map(fn(e) { format_literal(e, indent, context) })
  "[" <> string.join(element_strs, ", ") <> "]"
}
