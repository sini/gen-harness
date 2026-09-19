# THE BATCH ASSERTER'S FAILURE MESSAGE, HELD AT THE THREE VALUE CLASSES THAT USED TO DEFEAT IT.
#
# WHAT THESE CELLS ENCODE. `checks.default`'s message ran `builtins.toJSON` over the failing
# cell's value. It fires ONLY on the failure arm, so it fired exactly when someone needed the
# answer — and it ABORTED on any value containing a function, which every nixpkgs-protocol option
# type does. Worse than withholding: Nix reports the abort at the LAMBDA'S BIRTHPLACE, so the
# trace named a THIRD REPOSITORY and `den-hoag-jwtb0` was filed against gen-merge for a red that
# was gen-schema's own.
#
# ★ THEY REACH IT THROUGH THE PUBLISHED SURFACE — `inputs.gen-harness.lib.failMessage` — and never
# through a file path, the same discipline `ci/relock-behaviour.nix` states for `lib.relock`. That
# is also the only reason these cells exist at all: bound inside `flakeModule.nix` the function
# was reachable only by a cell FAILING, so every value it was ever read at was one that had
# already taken the gate down.
#
# ★ THE SUBJECT IS A REAL `lib.types` RECORD, NOT A HAND-WRITTEN `{ f = x: x; }`. The class is
# defined by the nixpkgs option protocol, and a fixture that merely happens to hold a lambda tests
# the spelling rather than the class. It is also what makes the cell decisive: a real option type
# is CYCLIC through `functor.type`, so it defeats a renderer that only answers the function half —
# which is the state the filed repair shape would have shipped.
#
# `genPrelude.hasInfix` rather than nixpkgs', by the standing convention mkCi states: the vendored
# one is backtracking-free, and there is no reason for this suite to hold the one exception.
{
  inputs,
  lib,
  genPrelude,
  ...
}:
let
  failMessage = inputs.gen-harness.lib.failMessage { inherit lib; };

  # A FAILING PAIR of the aborting class: both sides are real option types, so both sides carry
  # the protocol's five functions AND the `functor.type` cycle, and both sides are rendered.
  typeMessage = failMessage "a-suite" "test-a-cell" {
    expr = lib.types.int;
    expected = lib.types.str;
  };
in
{
  flake.tests.fail-message = {
    # ★ THE FUNCTION HALF. Forcing this string is what `toJSON` could not survive.
    test-a-type-record-renders-its-functions-instead-of-aborting = {
      expr = genPrelude.hasInfix "<function>" typeMessage;
      expected = true;
    };

    # ★ THE CYCLE HALF, AND IT IS A SEPARATE DEFECT FROM THE ONE ABOVE. `toPretty` answers the
    # function class and STACK-OVERFLOWS on this one; only the depth cut survives it. The cell
    # above cannot catch a renderer that has lost the cut, because a message that overflows never
    # reaches either assertion — so the evidence the cut is live is the ellipsis below, on a value
    # deeper than the cut, and not the mere fact that these cells are green.
    test-a-side-deeper-than-the-cut-is-elided-rather-than-walked = {
      expr = genPrelude.hasInfix "{ … }" (
        failMessage "s" "test-t" {
          expr = {
            a.b.c.d.e.f.g.h = 1;
          };
          expected = 0;
        }
      );
      expected = true;
    };

    # ★ THE THROW HALF. `==` SHORT-CIRCUITS, so a throwing field the comparison never reached is
    # first forced by the renderer. It must cost that ONE SIDE and not the message.
    test-a-throwing-side-costs-that-side-and-not-the-message = {
      expr = failMessage "s" "test-t" {
        expr = {
          a = throw "a cell's own throw, reached only by the renderer";
        };
        expected = 0;
      };
      expected = "FAIL s.test-t: got <unprintable: rendering this side threw>, expected 0";
    };

    # ★ THE NAMING HALF, AND IT IS THE FINDING THE OTHERS EXIST FOR. A message that renders but
    # does not say WHICH cell failed leaves the operator exactly where the abort did.
    test-the-message-names-the-failing-cell = {
      expr = genPrelude.hasInfix "FAIL a-suite.test-a-cell:" typeMessage;
      expected = true;
    };

    # The discriminating partner of all four: an ordinary value must still show BOTH SIDES. A
    # formatter that printed the coordinate and elided everything else would pass every cell
    # above, and one that rendered only `expr` would pass all but this.
    #
    # SCALARS DELIBERATELY. `toPretty` lays containers out over several lines, and a literal
    # pinning that layout would make this cell a change-detector for a nixpkgs internal rather
    # than for this repository's formatter — the same reason the type cells above assert an infix
    # instead of a whole message.
    test-an-ordinary-value-still-shows-both-sides = {
      expr = failMessage "s" "test-t" {
        expr = 1;
        expected = "two";
      };
      expected = ''FAIL s.test-t: got 1, expected "two"'';
    };
  };
}
