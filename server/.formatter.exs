[
  inputs: [
    "mix.exs",
    "apps/*/{mix,.formatter}.exs"
  ] ++
    (Path.wildcard("apps/*/{config,lib,test}/**/*.{ex,exs}") --
       Path.wildcard("apps/*/test/fixtures/**/*.{ex,exs}"))
]
