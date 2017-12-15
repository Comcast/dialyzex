# dialyzex

[![Build Status](https://travis-ci.org/Comcast/dialyzex.svg?branch=master)](https://travis-ci.org/Comcast/dialyzex)

This project adds a `mix dialyzer` task to your project. In addition
to simply automating dialyzer for Elixir projects, it provides some
features that existing solutions may not:

* Layered construction and validation of global PLTs for Erlang/OTP,
  Elixir, and a local PLT for project dependencies.
* Friendly ANSI-colored output.
* Exits non-zero when dialyzer produces warnings (good for continuous
  integration usage).
* Defaults to the strictest set of warnings available in Dialyzer,
  except for the few that are overly expensive.
* Ability to ignore acceptable warnings based on match patterns. For example,
  to ignore warnings produced by protocol compilation:
  ```elixir
  # Ignore dialyzer warnings about compiler generated specs for Protocols
  {:warn_contract_supertype, :_, {:extra_range, [:_, :__protocol__, 1, :_, :_]}}
  ```

For more details, consult `mix help dialyzer` after installation.

## Installation

`dialyzex` is available for installation
from [Hex](https://hex.pm). The package can be installed by adding
`dialyzex` to your list of dependencies in `mix.exs`:

```elixir
  def deps do
    [
      {:dialyzex, "~> 1.0.0", only: :dev}
    ]
  end
```

## Documentation

Documentation is generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm) at
[https://hexdocs.pm/dialyzex](https://hexdocs.pm/dialyzex).

## Contributing

If you would like to contribute code to this project you can do so
through GitHub by forking the repository and sending a pull
request. Before Comcast merges your code into the project you must
sign the Comcast Contributor License Agreement (CLA). If you haven't
previously signed a Comcast CLA, you'll automatically be asked to when
you open a pull request. Alternatively, we can e-mail you a PDF that
you can sign and scan back to us. Please send us an e-mail or create a
new GitHub issue to request a PDF version of the CLA.

## Copyright & License

Copyright 2017 Comcast Cable Communications Management, LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

This product includes software developed at Comcast (http://www.comcast.com/).
