# THE BASE MDFORMAT PLUGIN SET — the representational invariants of markdown this ecosystem
# defends, and the one place that says which plugins are members.
#
# Each member answers what a construct MEANS, not how it looks:
#   · frontmatter    — a leading `---` block is STRUCTURED DATA. Without it mdformat reads that
#                      block as a thematic break plus a heading and rewrites it; one
#                      repository's frontmatter was destroyed exactly that way, and the gate
#                      stayed green afterwards because the damage is idempotent.
#   · footnote       — a `[^1]:` line is a FOOTNOTE DEFINITION; without it the construct is
#                      escaped. Measured protective rather than cosmetic.
#   · simple-breaks  — a thematic break renders as `---` rather than the underscore run.
#   · gfm            — a `|`-delimited row is a TABLE ROW. Without it the row is ordinary prose,
#                      where `\|` is a redundant escape the formatter normalises away — so a
#                      cell holding a literal pipe silently becomes several cells the next time
#                      the document is rendered. Measured on a real row: 2 cells against a
#                      2-column header became 5. This ecosystem's markdown is read as
#                      GitHub-flavoured markdown, which is what makes the escape required rather
#                      than decorative.
#
# ★ The omission is a decision: `beautysh` is rejected because it reports `ERROR` while exiting
# 0, which is the silent-failure class this set's own guard removes. That ground is independent
# of gfm's disposition — it rejected beautysh while gfm was excluded and it rejects it now that
# gfm is a member, so beautysh does not arrive on gfm's coat-tails through its dependency edge.
#
# ★ WHY MEMBERSHIP IS WRITTEN ONCE, AS NAMES. The set had four independent hand-maintained
# statements of its own membership — the list, the guard's shell loop, the extraPlugins option
# description, and a sentence claiming gfm was per-corpus. Two of them went stale the day gfm
# joined, and two separate repairs each closed one without noticing the others, because the
# survivors were prose rather than lists. `names` is now the only membership fact: the plugin
# list is built from it and the guard is handed it, so neither can lag. Anything that describes
# what a member DOES belongs here, beside the names; anything that asserts WHICH things are
# members has nowhere else to live.
rec {
  # The membership fact. Every other statement of it in this repository is derived from here.
  names = [
    "mdformat-footnote"
    "mdformat-frontmatter"
    "mdformat-gfm"
    "mdformat-simple-breaks"
  ];

  # The `programs.mdformat.plugins` value, built from `names` rather than restating it.
  plugins = p: map (n: p.${n}) names;
}
