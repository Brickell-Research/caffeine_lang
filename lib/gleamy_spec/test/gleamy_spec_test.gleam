import gleamy_spec
import gleamy_spec/should

pub fn main() {
  gleamy_spec.main()
}

pub fn basic_proxy_test() {
  // Test that our proxy works correctly
  1
  |> should.equal(1)
}

pub fn should_module_test() {
  // Test that our should module re-exports work
  True
  |> should.be_true()

  False
  |> should.be_false()

  Ok("success")
  |> should.be_ok()

  Error("failure")
  |> should.be_error()
}
