pub type Query {
  Query(exp: Exp)
}

pub type ExpContainer {
  ExpContainer(exp: Exp)
}

pub type Operator {
  Add
  Sub
  Mul
  Div
}

pub type Exp {
  OperatorExpr(numerator: Exp, denominator: Exp, operator: Operator)
  Primary(primary: Primary)
}

pub type Primary {
  PrimaryWord(word: Word)
  PrimaryExp(exp: Exp)
}

pub type Word {
  Word(value: String)
}
