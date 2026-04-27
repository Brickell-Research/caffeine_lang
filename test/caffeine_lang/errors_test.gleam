import caffeine_lang/constants
import caffeine_lang/errors.{type CompilationError, ErrorCode}
import caffeine_lang/types
import caffeine_lang/value
import gleam/list
import gleam/option
import gleeunit/should
import test_helpers

// ==== error_code_to_string ====
// * ✅ three digit number
// * ✅ two digit number (pads)
// * ✅ single digit number (pads)
pub fn error_code_to_string_test() {
  [
    #("three digit number", ErrorCode("parse", 103), "E103"),
    #("two digit number (pads)", ErrorCode("cql", 42), "E042"),
    #("single digit number (pads)", ErrorCode("test", 1), "E001"),
  ]
  |> test_helpers.table_test_1(errors.error_code_to_string)
}

// ==== error_code_for ====
// * ✅ frontend parse error
// * ✅ frontend validation error
// * ✅ linker vendor resolution error
// * ✅ codegen error
// * ✅ cql error
pub fn error_code_for_test() {
  [
    #(
      "frontend parse error",
      errors.FrontendParseError(msg: "test", context: errors.empty_context()),
      ErrorCode("parse", 100),
    ),
    #(
      "frontend validation error",
      errors.FrontendValidationError(
        msg: "test",
        context: errors.empty_context(),
      ),
      ErrorCode("validation", 200),
    ),
    #(
      "linker vendor resolution error",
      errors.LinkerVendorResolutionError(
        msg: "test",
        context: errors.empty_context(),
      ),
      ErrorCode("linker", 304),
    ),
    #(
      "codegen error",
      errors.GeneratorTerraformResolutionError(
        vendor: constants.vendor_datadog,
        msg: "test",
        context: errors.empty_context(),
      ),
      ErrorCode("codegen", 502),
    ),
    #(
      "cql error",
      errors.CQLParserError(msg: "test", context: errors.empty_context()),
      ErrorCode("cql", 602),
    ),
  ]
  |> test_helpers.table_test_1(errors.error_code_for)
}

// ==== Format Decode Error Message Tests ====
// * ✅ empty list
// * ✅ single error with path, no identifier
// * ✅ single error without path, no identifier (shows "Unknown")
// * ✅ single error without path, with identifier (shows identifier)
// * ✅ single error with path, with identifier (path takes precedence)
// * ✅ multiple errors
pub fn format_validation_error_message_test() {
  [
    // empty list
    #("empty list", [], option.None, option.None, ""),
    // single error with path, no identifier, no value
    #(
      "single error with path, no identifier",
      [types.ValidationError("String", "Int", ["field"])],
      option.None,
      option.None,
      "expected (String) received (Int) for (field)",
    ),
    // single error without path, no identifier (shows "Unknown")
    #(
      "single error without path, no identifier (shows Unknown)",
      [types.ValidationError("String", "Int", [])],
      option.None,
      option.None,
      "expected (String) received (Int) for (Unknown)",
    ),
    // single error without path, with identifier (shows identifier)
    #(
      "single error without path, with identifier (shows identifier)",
      [types.ValidationError("String", "Int", [])],
      option.Some("my_field"),
      option.None,
      "expected (String) received (Int) for (my_field)",
    ),
    // single error with path, with identifier (combined: identifier.path)
    #(
      "single error with path, with identifier (path takes precedence)",
      [types.ValidationError("String", "Int", ["actual", "path"])],
      option.Some("my_identifier"),
      option.None,
      "expected (String) received (Int) for (my_identifier.actual.path)",
    ),
    // multiple errors
    #(
      "multiple errors",
      [
        types.ValidationError("String", "Int", ["first"]),
        types.ValidationError("Bool", "Float", ["second"]),
      ],
      option.None,
      option.None,
      "expected (String) received (Int) for (first), expected (Bool) received (Float) for (second)",
    ),
    // single error with value preview (string)
    #(
      "single error with value preview (string)",
      [types.ValidationError("Int", "String", [])],
      option.Some("my_field"),
      option.Some(value.StringValue("hello")),
      "expected (Int) received (String) value (\"hello\") for (my_field)",
    ),
    // single error with value preview (int)
    #(
      "single error with value preview (int)",
      [types.ValidationError("String", "Int", [])],
      option.Some("count"),
      option.Some(value.IntValue(42)),
      "expected (String) received (Int) value (42) for (count)",
    ),
    // single error with value preview (bool)
    #(
      "single error with value preview (bool)",
      [types.ValidationError("String", "Bool", [])],
      option.Some("flag"),
      option.Some(value.BoolValue(True)),
      "expected (String) received (Bool) value (true) for (flag)",
    ),
  ]
  |> test_helpers.table_test_3(errors.format_validation_error_message)
}

// ==== smart constructors ====
// * ✅ each constructor creates correct variant with empty context
pub fn smart_constructors_test() {
  let ctx = errors.empty_context()

  errors.frontend_parse_error(msg: "a")
  |> should.equal(errors.FrontendParseError(msg: "a", context: ctx))

  errors.frontend_validation_error(msg: "b")
  |> should.equal(errors.FrontendValidationError(msg: "b", context: ctx))

  errors.linker_value_validation_error(msg: "c")
  |> should.equal(errors.LinkerValueValidationError(msg: "c", context: ctx))

  errors.linker_duplicate_error(msg: "d")
  |> should.equal(errors.LinkerDuplicateError(msg: "d", context: ctx))

  errors.linker_parse_error(msg: "e")
  |> should.equal(errors.LinkerParseError(msg: "e", context: ctx))

  errors.linker_vendor_resolution_error(msg: "f")
  |> should.equal(errors.LinkerVendorResolutionError(msg: "f", context: ctx))

  errors.semantic_analysis_template_parse_error(msg: "g")
  |> should.equal(errors.SemanticAnalysisTemplateParseError(
    msg: "g",
    context: ctx,
  ))

  errors.semantic_analysis_template_resolution_error(msg: "h")
  |> should.equal(errors.SemanticAnalysisTemplateResolutionError(
    msg: "h",
    context: ctx,
  ))

  errors.semantic_analysis_dependency_validation_error(msg: "i")
  |> should.equal(errors.SemanticAnalysisDependencyValidationError(
    msg: "i",
    context: ctx,
  ))

  errors.generator_slo_query_resolution_error(msg: "j")
  |> should.equal(errors.GeneratorSloQueryResolutionError(
    msg: "j",
    context: ctx,
  ))

  errors.generator_terraform_resolution_error(vendor: "datadog", msg: "k")
  |> should.equal(errors.GeneratorTerraformResolutionError(
    vendor: "datadog",
    msg: "k",
    context: ctx,
  ))

  errors.cql_resolver_error(msg: "l")
  |> should.equal(errors.CQLResolverError(msg: "l", context: ctx))

  errors.cql_parser_error(msg: "m")
  |> should.equal(errors.CQLParserError(msg: "m", context: ctx))
}

// ==== error_code_for - all vendor codes ====
// * ✅ Datadog → E502
// * ✅ Unknown vendor → E500
pub fn error_code_for_all_vendors_test() {
  [
    #(
      "Datadog",
      errors.GeneratorTerraformResolutionError(
        vendor: constants.vendor_datadog,
        msg: "x",
        context: errors.empty_context(),
      ),
      ErrorCode("codegen", 502),
    ),
    #(
      "Unknown vendor",
      errors.GeneratorTerraformResolutionError(
        vendor: "fake_vendor",
        msg: "x",
        context: errors.empty_context(),
      ),
      ErrorCode("codegen", 500),
    ),
  ]
  |> test_helpers.table_test_1(errors.error_code_for)
}

// ==== error_code_for - remaining variants ====
// * ✅ linker value validation → E302
// * ✅ linker duplicate → E303
// * ✅ linker parse → E301
// * ✅ semantic template parse → E402
// * ✅ semantic template resolution → E403
// * ✅ semantic dependency validation → E404
// * ✅ generator slo query resolution → E501
// * ✅ cql resolver → E601
// * ✅ CompilationErrors → E000
pub fn error_code_for_remaining_variants_test() {
  [
    #(
      "linker value validation",
      errors.linker_value_validation_error(msg: "x"),
      ErrorCode("linker", 302),
    ),
    #(
      "linker duplicate",
      errors.linker_duplicate_error(msg: "x"),
      ErrorCode("linker", 303),
    ),
    #(
      "linker parse",
      errors.linker_parse_error(msg: "x"),
      ErrorCode("linker", 301),
    ),
    #(
      "semantic template parse",
      errors.semantic_analysis_template_parse_error(msg: "x"),
      ErrorCode("semantic", 402),
    ),
    #(
      "semantic template resolution",
      errors.semantic_analysis_template_resolution_error(msg: "x"),
      ErrorCode("semantic", 403),
    ),
    #(
      "semantic dependency validation",
      errors.semantic_analysis_dependency_validation_error(msg: "x"),
      ErrorCode("semantic", 404),
    ),
    #(
      "generator slo query resolution",
      errors.generator_slo_query_resolution_error(msg: "x"),
      ErrorCode("codegen", 501),
    ),
    #(
      "cql resolver",
      errors.cql_resolver_error(msg: "x"),
      ErrorCode("cql", 601),
    ),
    #(
      "CompilationErrors",
      errors.CompilationErrors(errors: []),
      ErrorCode("multiple", 0),
    ),
  ]
  |> test_helpers.table_test_1(errors.error_code_for)
}

// ==== error_context ====
// * ✅ extracts context from single-error variant
// * ✅ returns empty context for CompilationErrors
pub fn error_context_test() {
  let ctx =
    errors.ErrorContext(
      identifier: option.Some("test"),
      source_path: option.None,
      source_content: option.None,
      location: option.None,
      suggestion: option.None,
    )
  let err = errors.FrontendParseError(msg: "x", context: ctx)

  errors.error_context(err)
  |> should.equal(ctx)

  errors.error_context(errors.CompilationErrors(errors: []))
  |> should.equal(errors.empty_context())
}

// ==== prefix_error ====
// * ✅ prepends identifier to message
// * ✅ sets context.identifier
// * ✅ preserves existing context.identifier
// * ✅ recurses into CompilationErrors
pub fn prefix_error_test() {
  let err = errors.frontend_parse_error(msg: "oops")
  let prefixed = errors.prefix_error(err, "my_file")

  errors.to_message(prefixed)
  |> should.equal("my_file - oops")

  errors.error_context(prefixed).identifier
  |> should.equal(option.Some("my_file"))

  // Double prefix preserves first identifier
  let double_prefixed = errors.prefix_error(prefixed, "outer")
  errors.error_context(double_prefixed).identifier
  |> should.equal(option.Some("my_file"))
  errors.to_message(double_prefixed)
  |> should.equal("outer - my_file - oops")

  // Recurses into CompilationErrors
  let multi =
    errors.CompilationErrors(errors: [
      errors.linker_parse_error(msg: "a"),
      errors.cql_parser_error(msg: "b"),
    ])
  let prefixed_multi = errors.prefix_error(multi, "id")
  case prefixed_multi {
    errors.CompilationErrors(errors:) -> {
      list.length(errors) |> should.equal(2)
      list.map(errors, errors.to_message)
      |> should.equal(["id - a", "id - b"])
    }
    _ -> should.fail()
  }
}

// ==== to_list ====
// * ✅ single error → one-element list
// * ✅ CompilationErrors → flattened list
// * ✅ nested CompilationErrors → recursively flattened
pub fn to_list_test() {
  let err1 = errors.frontend_parse_error(msg: "a")
  let err2 = errors.linker_parse_error(msg: "b")

  errors.to_list(err1) |> should.equal([err1])

  errors.to_list(errors.CompilationErrors(errors: [err1, err2]))
  |> should.equal([err1, err2])

  // Nested
  let inner = errors.CompilationErrors(errors: [err1])
  errors.to_list(errors.CompilationErrors(errors: [inner, err2]))
  |> should.equal([err1, err2])
}

// ==== to_message ====
// * ✅ single error → message string
// * ✅ CompilationErrors → joined messages
pub fn to_message_test() {
  errors.to_message(errors.frontend_parse_error(msg: "hello"))
  |> should.equal("hello")

  errors.to_message(
    errors.CompilationErrors(errors: [
      errors.frontend_parse_error(msg: "first"),
      errors.linker_parse_error(msg: "second"),
    ]),
  )
  |> should.equal("first\nsecond")
}

// ==== from_results ====
// * ✅ all Ok → Ok with values
// * ✅ single Error → Error with that error
// * ✅ multiple Errors → Error(CompilationErrors)
pub fn from_results_test() {
  let results_ok: List(Result(Int, CompilationError)) = [Ok(1), Ok(2), Ok(3)]
  errors.from_results(results_ok)
  |> should.equal(Ok([1, 2, 3]))

  let err1 = errors.frontend_parse_error(msg: "bad")
  let results_one_error: List(Result(Int, CompilationError)) = [
    Ok(1),
    Error(err1),
    Ok(3),
  ]
  errors.from_results(results_one_error)
  |> should.equal(Error(err1))

  let err2 = errors.linker_parse_error(msg: "also bad")
  let results_multi_error: List(Result(Int, CompilationError)) = [
    Error(err1),
    Ok(2),
    Error(err2),
  ]
  errors.from_results(results_multi_error)
  |> should.equal(Error(errors.CompilationErrors(errors: [err1, err2])))
}
