import caffeine_lang/generator/common
import test_helpers

// ==== sanitize_terraform_identifier ====
// * ✅ replaces slashes with underscores
// * ✅ replaces spaces with underscores
// * ✅ replaces commas with underscores
// * ✅ replaces apostrophes with underscores
// * ✅ preserves hyphens (valid in terraform identifiers)
// * ✅ handles simple names without modification
// * ✅ prefixes with underscore if starts with digit
// * ✅ replaces other special characters
pub fn sanitize_terraform_identifier_test() {
  [
    #("org/team/auth/latency", "org_team_auth_latency"),
    #("my slo name", "my_slo_name"),
    #("my slo, name", "my_slo__name"),
    #("my slo's name", "my_slo_s_name"),
    #("my slo-name", "my_slo-name"),
    #("simple_name", "simple_name"),
    #("123_resource", "_123_resource"),
    #("0invalid", "_0invalid"),
    #("name@domain", "name_domain"),
    #("foo.bar", "foo_bar"),
    #("test:value", "test_value"),
    #("a+b=c", "a_b_c"),
    #("(grouped)", "_grouped_"),
    #("[array]", "_array_"),
  ]
  |> test_helpers.array_based_test_executor_1(common.sanitize_terraform_identifier)
}
