import caffeine_lang_v2/parser/artifacts.{type Artifact}
import caffeine_lang_v2/parser/blueprints.{type Blueprint}
import caffeine_lang_v2/parser/expectations.{type ServiceExpectation}

pub type AST {
  AST(
    artifacts: List(Artifact),
    blueprints: List(Blueprint),
    expectations: List(ServiceExpectation),
  )
}
