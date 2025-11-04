import gleamy_spec/should

pub fn assert_parse_error(
  parser: fn(String) -> Result(a, String),
  file_path: String,
  expected: String,
) {
  let actual = parser(file_path)
  actual
  |> should.equal(Error(expected))
}
