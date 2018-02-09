# Copyright 2017 Comcast Cable Communications Management, LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
defmodule Mix.Tasks.Dialyzer do
  use Mix.Task
  require IEx

  @shortdoc "Runs static analysis via dialyzer"

  @moduledoc """
  Prepares and runs static analysis of application code via
  `dialyzer`.

  ## PLT Creation

  For efficiency, we construct multiple disjunct PLTs: one for Erlang
  and the runtime system (ERTS), one for Elixir, and one for the
  transitive dependencies of the project. The rationale here is that
  the Erlang installation, Elixir installation, and the dependencies
  of the project have different lifetimes. Erlang and Elixir, for
  example, would not change across builds of the same project, but a
  dependency might. Additionally, analyzing the standard library in
  order to construct a PLT is expensive and should be done
  infrequently.

  The Erlang and Elixir PLTs are stored in a hidden subdirectory of
  the user's home directory, namely `~/.cache/dialyzer/plts`. The
  contents of that directory after building PLTs might look like the
  below:

  ```shell
  $ ls ~/.cache/dialyzer/plts/
  elixir-1.4.2.plt    erlang-19-erts-8.2.2.plt
  ```

  The dependencies PLT is stored in the build directory of the current
  `Mix.env`, e.g. `_build/dev/deps-31440056.plt`.

  ## Warnings

  All non-default recommended warnings are turned on, equivalent to
  these command-line flags to dialyzer:

      -Wunmatched_returns -Werror_handling -Wrace_conditions -Wunderspecs -Wunknown

  Warnings can be customized using the `:dialyzer_warnings` config key
  in the Mix project configuration.

  If warnings are emitted from analysis, the task will exit
  non-zero. In some cases, there are particular warning signatures
  that are acceptable and should not cause failure of an automated
  build. These signatures can be matched and ignored via the
  `:dialyzer_ignored_warnings` setting. The format of this list are
  match patterns of the warning tuples produced by dialyzer:

      {tag, {file, line}, {warning_type, arguments}}

  The warning tuples coming from your analysis can be printed by
  turning debug mode on:

      $ MIX_DEBUG=1 mix dialyzer --check=false
      # [snip]
      Running analysis...
      Errors:
        ct.ex:177: The created fun only terminates with explicit exception
        dialyzer.ex:282: The created fun only terminates with explicit exception

      IGNORED WARNINGS:
      []
      FAILURES:
      [{:warn_return_only_exit, {'lib/mix/tasks/ct.ex', 177},
        {:no_return, [:only_explicit]}},
       {:warn_return_only_exit, {'lib/mix/tasks/dialyzer.ex', 282},
        {:no_return, [:only_explicit]}}]
      FAILURE: 2 failures.

  From those tuples, you can determine how to construct the match
  pattern. If one wanted to ignore the first failure, the following
  pattern would work:

      {:warn_return_only_exit, {'lib/mix/tasks/ct.ex', :_}, {:no_return, :_}}

  For fields of the tuple that aren't important to distinguish, use
  `:_` to match all patterns in that space. See OTP's documentation on
  match patterns and specs for more details.

  ## Options

  * `--check=(true|false)`: enable/disable checking of existing PLTs
    (default: `true`)
  * `--compile=(true|false)`: enable/disable compilation of the
    project (default: `true`)

  ## Caveats

  If checking an existing PLT fails (e.g. a dependency changed), *you
  must remove the PLT to force a rebuild.* This caveat is mitigated
  for the shared PLTs by naming them after their respective versions,
  which are assumed to be stable, and the dependency PLT after the
  hash of the lockfile contents (somewhat). In future versions, we
  could add or remove information from the PLTs as needed.

  """

  @switches [
    compile: :boolean,
    check: :boolean
  ]

  # This isn't ideal, but we need to exclude eqc and anything else
  # non-OTP from the PLT, so we can't use :code.lib_dir() directly.
  @erlang_core_apps ~w(
    asn1 common_test compiler cosEvent cosEventDomain cosFileTransfer
    cosNotification cosProperty cosTime cosTransactions crypto
    debugger dialyzer diameter edoc eldap erl_docgen erl_interface
    erts et eunit hipe ic inets kernel megaco mnesia observer odbc
    orber os_mon parsetools public_key reltool runtime_tools sasl snmp
    ssh ssl stdlib syntax_tools tools wx xmerl
  )a

  @elixir_core_apps [:eex, :elixir, :ex_unit, :iex, :logger, :mix]

  @default_warnings [:unmatched_returns, :error_handling, :race_conditions, :underspecs, :unknown]

  def run(args) do
    {opts, _, []} = OptionParser.parse(args, switches: @switches)

    # Ensure project is compiled
    if Keyword.get(opts, :compile, true) do
      Mix.Project.compile(args)
    end

    # Construct or verify existing PLTs
    check = Keyword.get(opts, :check, true)

    _ = check_or_build(otp_plt_name(), &otp_app_paths/0, "Erlang/OTP", check, [])
    _ = check_or_build(elixir_plt_name(), &elixir_paths/0, "Elixir", check, [otp_plt_name()])
    _ = check_or_build(deps_plt_name(), &deps_paths/0, "dependencies", check, [elixir_plt_name()])

    # Run analysis
    # Turns match_pattern into a match_spec that returns true
    whitelist =
      Mix.Project.config()
      |> Keyword.get(:dialyzer_ignored_warnings, [])
      |> Enum.map(&{&1, [], [true]})

    warnings =
      Mix.Project.config()
      |> Keyword.get(:dialyzer_warnings, @default_warnings)

    Mix.shell().info("Running analysis...")

    analysis =
      dialyze(
        analysis_type: :succ_typings,
        plts: [otp_plt_name(), elixir_plt_name(), deps_plt_name()],
        files_rec: apps_paths(),
        warnings: warnings,
        fail_on_warning: true,
        whitelist: whitelist
      )

    if Mix.debug?() do
      {ignored, failed} = analysis
      Mix.shell().info("IGNORED WARNINGS:")
      Mix.shell().info(inspect(ignored, pretty: true))
      Mix.shell().info("FAILURES:")
      Mix.shell().info(inspect(failed, pretty: true))
    end

    analysis
    |> format_results
    |> Mix.shell().info
  end

  defp format_results({[], []}) do
    [:green, "SUCCESS: No failures or warnings."]
  end

  defp format_results({ignored, []}) do
    [:green, "SUCCESS: ", :yellow, "#{length(ignored)} warnings."]
  end

  defp format_results({[], failed}) do
    [:red, "FAILURE: #{length(failed)} failures."]
  end

  defp format_results({ignored, failed}) do
    [:red, "FAILURE: #{length(failed)} failures, ", :yellow, "#{length(ignored)} warnings."]
  end

  defp check_or_build(plt_file, paths, name, check, input_plts) do
    cond do
      File.exists?(plt_file) && check ->
        check_plt(plt_file, name)

      File.exists?(plt_file) ->
        {[], []}

      true ->
        build_plt(plt_file, paths.(), name, input_plts)
    end
  end

  defp build_plt(file, paths, name, init_plts) do
    Mix.shell().info("Building #{name} PLT: #{file}")
    :ok = :filelib.ensure_dir(file)

    dialyze(
      analysis_type: :plt_build,
      output_plt: file,
      plts: init_plts,
      files_rec: paths
    )
  end

  defp check_plt(file, name) do
    Mix.shell().info("Checking #{name} PLT: #{file}")
    dialyze(analysis_type: :plt_check, init_plt: file)
  end

  defp dialyze(opts) do
    {report_opts, options} = Keyword.split(opts, [:fail_on_warning, :whitelist])

    try do
      options |> :dialyzer.run() |> report_warnings(report_opts)
    catch
      :throw, {:dialyzer_error, failure} ->
        Mix.raise(:erlang.iolist_to_binary(failure))
    end
  end

  defp otp_app_paths do
    Enum.reduce(@erlang_core_apps, [], fn app, paths ->
      case :code.lib_dir(app) do
        {:error, :bad_name} ->
          Mix.shell().error(
            "Could not find library directory for application #{inspect(app)}. It will not be included in the PLT."
          )

          paths

        dir ->
          [dir | paths]
      end
    end)
  end

  defp otp_plt_name do
    cache_directory()
    |> Path.join("erlang-#{System.otp_release()}-erts-#{:erlang.system_info(:version)}.plt")
    |> String.to_charlist()
  end

  defp elixir_plt_name do
    cache_directory()
    |> Path.join(
      "elixir-#{System.version()}-erlang-#{System.otp_release()}-erts-#{
        :erlang.system_info(:version)
      }.plt"
    )
    |> String.to_charlist()
  end

  defp elixir_paths do
    @elixir_core_apps
    |> Enum.map(&:code.lib_dir/1)
  end

  defp deps_plt_name do
    hash =
      Mix.Dep.Lock.read()
      |> :erlang.term_to_binary()
      |> List.wrap()
      |> Enum.concat([elixir_plt_name()])
      |> :erlang.md5()
      |> Base.url_encode64(padding: false)

    Mix.Project.build_path()
    |> Path.join("deps-#{hash}.plt")
    |> String.to_charlist()
  end

  defp deps_paths do
    [env: Mix.env(), include_children: true]
    |> Mix.Dep.loaded()
    |> Enum.reject(fn dep -> dep.opts[:from_umbrella] end)
    |> Enum.flat_map(&Mix.Dep.load_paths/1)
    |> Enum.map(&String.to_charlist/1)
  end

  defp apps_paths do
    paths =
      if Mix.Project.umbrella?() do
        Mix.Dep.cached()
        |> Enum.filter(fn dep -> dep.opts[:from_umbrella] end)
        |> Enum.flat_map(&Mix.Dep.load_paths/1)
      else
        # TODO: Do we include consolidated protocols in the analysis? If
        # so, we need to use the root build_path. However, this could
        # trigger warnings about protocols from the Elixir stdlib. See
        # also: https://github.com/elixir-lang/elixir/pull/5679
        [Mix.Project.app_path()]
      end

    Enum.map(paths, &String.to_charlist/1)
  end

  defp report_warnings([], _report_opts) do
    []
  end

  defp report_warnings(warnings, report_opts) do
    fail_on_warning = Keyword.get(report_opts, :fail_on_warning, false)
    whitelist = Keyword.get(report_opts, :whitelist, [])

    {ignored, failures} = Enum.split_with(warnings, &warning_matches?(&1, whitelist))

    if fail_on_warning && failures != [] do
      # Exit non-zero when warnings exist
      System.at_exit(fn _ -> exit({:shutdown, 1}) end)
    end

    unless ignored == [] do
      warnings = Enum.map_join(ignored, "\n", &format_warning/1)
      Mix.shell().info([:yellow, "Warnings:\n", warnings, "\n"])
    end

    unless failures == [] do
      errors = Enum.map_join(failures, "\n", &format_warning/1)
      Mix.shell().info([:red, "Errors:\n", errors, "\n"])
    end

    {ignored, failures}
  end

  # If we don't special-case these warnings, we get printouts like:
  #  :0: Unknown type: foo:bar/1
  #  :0: Unknown function: not:a_fun/3
  #  :0: Unknown behaviour: some_mod
  # The line number is irrelevant in these cases.

  defp format_warning({_tag, {_file, _line}, {:unknown_type, {m, f, a}}}) do
    indent("Unknown type: #{m}:#{f}/#{a}")
  end

  defp format_warning({_tag, {_file, _line}, {:unknown_function, {m, f, a}}}) do
    indent("Unknown function: #{m}:#{f}/#{a}")
  end

  defp format_warning({_tag, {_file, _line}, {:unknown_behaviour, b}}) do
    indent("Unknown behaviour: #{b}")
  end

  defp format_warning(w) do
    w
    |> :dialyzer.format_warning(:fullpath)
    |> to_string
    |> String.trim()
    |> indent
  end

  defp indent(string, amount \\ 2) do
    String.duplicate(" ", amount) <> string
  end

  defp cache_directory do
    Path.join([System.user_home(), ".cache", "dialyzer", "plts"])
  end

  defp warning_matches?(warning, pattern) do
    # From docs on erlang:match_spec_test/3:
    #
    # If Type is table, the object to match against is to be a
    # tuple. The function then returns {ok,Result,[],Warnings}, where
    # Result is what would have been the result in a real ets:select/2
    # call, or false if the match specification does not match the
    # object tuple.
    case :erlang.match_spec_test(warning, pattern, :table) do
      {:error, _} -> false
      {:ok, false, _, _} -> false
      {:ok, true, _, _} -> true
    end
  end
end
