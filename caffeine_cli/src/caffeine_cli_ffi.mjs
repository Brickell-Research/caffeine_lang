// JS equivalent for erlang's halt/1. See: https://www.erlang.org/doc/apps/erts/erlang.html#halt/1
export function halt(code) {
  process.exit(code);
}
