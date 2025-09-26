import startest/expect

pub fn assert_parse_error(
  parser: fn(String) -> Result(a, String),
  file_path: String,
  expected: String,
) {
  let actual = parser(file_path)
  expect.to_equal(actual, Error(expected))
}
