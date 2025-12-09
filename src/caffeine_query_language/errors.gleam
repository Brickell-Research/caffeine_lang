pub type CQLError {
  CQLResolverError(msg: String)
  CQLParserError(msg: String)
  CQLGeneratorError(msg: String)
}
