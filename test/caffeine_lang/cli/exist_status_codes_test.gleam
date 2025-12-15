import caffeine_lang/cli/exit_status_codes
import test_helpers

// ==== Exist Status Code to Int ====
// * ✅ Success
// * ✅ Failure
// Probably overkill but 🤷‍♂️
pub fn exist_status_code_to_int_test() {
  test_helpers.array_based_test_executor_1(
    [
      #(exit_status_codes.Success, 0),
      #(exit_status_codes.Failure, 1),
    ],
    exit_status_codes.exist_status_code_to_int,
  )
}
