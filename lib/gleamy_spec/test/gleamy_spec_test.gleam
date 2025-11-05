import gleamy_spec
import gleamy_spec/extensions.{describe}
import gleamy_spec/gleeunit

pub fn main() {
  gleamy_spec.main()
}

pub fn basic_proxy_test() {
  // Test that our proxy works correctly
  1
  |> gleeunit.equal(1)
}

pub fn should_module_test() {
  // Test that our should module re-exports work
  True
  |> gleeunit.be_true()

  False
  |> gleeunit.be_false()

  Ok("success")
  |> gleeunit.be_ok()

  Error("failure")
  |> gleeunit.be_error()
}

pub fn describe_module_test() {
  // Single level describe block
  describe("describe module", fn() {
    Ok(1)
    |> gleeunit.equal(Ok(1))
  })

  // Nested describe blocks
  describe("outer describe", fn() {
    describe("inner describe", fn() {
      Ok(1)
      |> gleeunit.equal(Ok(1))
    })

    describe("another inner describe", fn() {
      Ok(2)
      |> gleeunit.equal(Ok(2))
    })
  })
}
