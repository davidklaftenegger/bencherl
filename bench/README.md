This is where all benchmarks reside.

### The structure of a benchmark directory ###

A benchmark directory contains:

* a `Makefile` that builds the benchmark;
* a `src` directory that contains the source code of the benchmark;
* a `data` directory that contains any external data that the benchmark needs for its execution;
* a `conf` directory that contains the `bench.conf`, the `pre_bench` and the `post_bench` scripts.

### The structure of a benchmark handler ###

The **benchmark handler** is a standard Erlang module that has the same name 
as the benchmark, is put in the `src` directory and is necessary for the 
execution of the benchmark.

A benchmark handler exports the following functions:

	%% Returns the different argument sets to use for running the specified
	%% version of the benchmark.
	bench_args(Version) -> Args
  		when
    		Args :: [[term()]],
    		Version :: short | intermediate | long.


	%% Uses the specified arguments, slave nodes and configuration settings
	%% to run the benchmark.
	run(Args, Slaves, Conf) -> ok | {error, Reason}
		when
			Args   :: [term()],
    		Slaves :: [node()],
    		Conf   :: [{Key :: atom(), Val :: term()}, ...],
    		Reason :: term().

### The purpose of the `pre_bench` script ###

This is a BASH script that is used to perform any actions before executing the 
benchmark in a new runtime environment.

### The purpose of the `post_bench` script ###

This is a BASH script that is used to perform any actions after the execution of
the benchmark in a runtime environment is complete.

### The purpose of the `bench.conf` script ###

This file contains new values, which are specific for this benchmark, for the 
following variables in `conf/run.conf`.
* `CHECK_SANITY`
* `COOKIE`
* `ERL_ARGS`
* `ITERATIONS`
* `NUMBER_OF_SLAVE_NODES`
* `NUMBER_OF_SCHEDULERS`
* `OTPS`
* `PLOT`
* `SLAVE_NODES`

This file may also set the following variables:
* `DEPENDENCIES`: This variable is used to specify the applications that are internal to `bencherl` (i.e. reside in the `app` directory) and that the benchmark depends on. Its value is zero or more application names separated with commas.
* `EXTRA_CODE_PATH`: This variable is used to specify any extra directories that should be added to the code path when running the benchmark. Its value is zero or more directories separated with spaces.
* `EXTRA_ERL_ARGS`: This variable is used to specify any extra command-line arguments that should be passed to the `erl` program when running the benchmark. Its value are the arguments separated with spaces.

