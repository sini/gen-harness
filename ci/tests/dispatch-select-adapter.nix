# THE gen-dispatch × gen-select PAIRING — gen-dispatch's `adapters.select` bridges dispatch
# conditions to gen-select's selector algebra (`mkMatch`, `selectorSpecificity`), and testing that
# bridge means evaluating it against a REAL gen-select, not a mock. That makes the suite a claim
# about two libraries at once, so it lives here rather than in either one's own ci: gen-dispatch
# pinning gen-select just to run this suite would make the sibling a declared dependency of a
# library whose adapter tier does not import it (the core tier is gen-select-free by construction).
# Pinned directly as this flake's own input instead, so the suite tracks one current gen-select
# rather than whatever revision gen-dispatch's own ci happened to carry — which is exactly how the
# pin this suite used to run at went five-plus weeks stale, testing an adapter against a gen-select
# surface that predated `entity`, `kind` and `adapters.product` entirely.
{
  lib,
  genDispatch,
  genSelect,
  ...
}:
let
  sel = genSelect;
  adapter = genDispatch.adapters.select;
  match = adapter.mkMatch genSelect;
  mockCtx = {
    data =
      id:
      {
        "host:web" = {
          type = "host";
          env = "prod";
        };
        "user:tux" = {
          type = "user";
        };
      }
      .${id};
    parent = id: { "user:tux" = "host:web"; }.${id} or null;
    children = id: { "host:web" = [ "user:tux" ]; }.${id} or [ ];
    ancestors = id: { "user:tux" = [ "host:web" ]; }.${id} or [ ];
    siblings = _: [ ];
  };
in
{
  flake.tests.dispatch-select-adapter = {
    test-match-attrs = {
      expr = match (sel.attrs { type = "host"; }) "host:web" mockCtx;
      expected = true;
    };

    test-match-attrs-no-match = {
      expr = match (sel.attrs { type = "user"; }) "host:web" mockCtx;
      expected = false;
    };

    test-match-restricted = {
      expr = match {
        __restricted = true;
        original = sel.attrs { type = "host"; };
        extra = sel.attrs { env = "prod"; };
      } "host:web" mockCtx;
      expected = true;
    };

    test-match-restricted-fails = {
      expr = match {
        __restricted = true;
        original = sel.attrs { type = "host"; };
        extra = sel.attrs { env = "staging"; };
      } "host:web" mockCtx;
      expected = false;
    };

    test-specificity-attrs = {
      expr = adapter.selectorSpecificity (
        sel.attrs {
          type = "host";
          env = "prod";
        }
      );
      expected = 2;
    };

    test-specificity-star = {
      expr = adapter.selectorSpecificity sel.star;
      expected = 0;
    };

    test-specificity-has = {
      expr = adapter.selectorSpecificity (sel.has (sel.attrs { type = "user"; }));
      expected = 2;
    };

    test-specificity-and = {
      expr = adapter.selectorSpecificity (
        sel.and [
          (sel.attrs { type = "host"; })
          (sel.attrs { env = "prod"; })
        ]
      );
      expected = 2;
    };

    test-specificity-when = {
      expr = adapter.selectorSpecificity (sel.when (_id: _ctx: true));
      expected = 0;
    };
  };
}
