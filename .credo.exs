# Credo configuration for Astro, following the Localize house rules.
#
# * `Design.AliasUsage` is disabled. Module names such as `Astro.Time`
#   and `Astro.Math` shadow the standard library when aliased, so many
#   calls are deliberately fully qualified.
#
# * `Refactor.Nesting` stays at the default maximum depth of 2:
#   multi-clause helper functions with pattern matching are preferred
#   over nested case/cond/if.
#
# * `Refactor.CyclomaticComplexity` stays at the default of 9;
#   naturally-branchy functions carry inline `credo:disable` annotations
#   with a one-line justification instead of a raised global limit.
#
# * `Refactor.Apply` stays enabled; legitimate dynamic dispatch is
#   annotated inline.
#
# * `Astro.Credo.NoTryRescue` (`credo/checks/no_try_rescue.ex`) reports
#   every `try` and every function-level `rescue`, `catch`, `else` or
#   `after`, apart from a `rescue` of `ArgumentError` around a lone
#   `String.to_existing_atom/1` call and the functions listed in
#   `:allowed_try_after`. Extending either needs its own reason.
%{
  configs: [
    %{
      name: "default",
      strict: true,
      files: %{
        included: ["lib/", "test/", "credo/"],
        excluded: []
      },
      plugins: [{ExSlop, []}],
      requires: ["credo/checks/no_try_rescue.ex"],
      checks: %{
        disabled: [
          {Credo.Check.Design.AliasUsage, []}
        ],
        extra:
          [
            {Astro.Credo.NoTryRescue, allowed_try_after: []}
          ] ++ Enum.map(ExSlop.recommended_checks(), &{&1, []})
      }
    }
  ]
}
