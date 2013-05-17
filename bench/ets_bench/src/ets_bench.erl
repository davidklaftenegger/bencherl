-module(ets_bench).

-export([bench_args/2, run/3]).

-define(BASE, 2).
-define(RAND_MAX, 65535).
-define(TABLE_PROCESS, table_process).

bench_args(Version, _) ->
	%% KeyRange, Inserts/Deletes and Reads as powers of ?BASE
	[KeyRange, InsDels, Reads, PartialResults] = case Version of
		short -> [14, 15, 16, 1];
		intermediate -> [18, 20, 22, 1];
		long -> [20, 24, 28, 1]
	end,
	TableTypes = case Version of
		short -> [set, ordered_set, {gi, null}];
		intermediate -> [set, ordered_set ];
		long -> [set, ordered_set ]
	end,
	%% use deterministic seed for reproducable results
	Seed = {0,0,0},
	%% use random seed for varying input
	%Seed = now(),
	ConcurrencyOptions = [no,rw], % options are: no, r, w, rw
	%[[TT,KeyRange,InsDels,Reads,C,PartialResults,Seed] || TT <- TableTypes, C <- ConcurrencyOptions ] ++ [[set,KeyRange,InsDels,Reads,rw,PartialResults,Seed], [ordered_set,KeyRange,InsDels,Reads,rw,PartialResults,Seed], [{gi, null},KeyRange,InsDels,Reads,rw,PartialResults,Seed]].
	[[TT,KeyRange,InsDels,Reads,C,PartialResults,Seed] || TT <- TableTypes, C <- ConcurrencyOptions ].

run([Type, _K, _W, _R, C, _Parts, Seed], _, _) ->
	% this is a setup
	{RC, WC} = case C of
		no -> {false, false};
		r -> {true, false};
		w -> {false, true};
		rw -> {true, true}
	end,
	ConcurrencyOptions = [{read_concurrency, RC}, {write_concurrency, WC}],
	{TableType, SubType} = case Type of
		{gi, Sub} -> {generic_interface, [{gi_type, Sub}]};
		_ -> {Type, []}
	end,
	Options = SubType ++ ConcurrencyOptions,
	Self = self(),
	spawn(fun() -> table_process(Self, [TableType, public | Options]) end),
	Table = receive {table, T} -> T end,
	
	{{continue, ignore}, [insert, Table, 0, Seed]};
run([[run | State ] | Config], _, _) ->
	%erlang:display(State ++ Config),
	run_bench(State ++ Config);
run(State, _, _) ->
	setup(State).

table_process(Pid, Opts) ->
	register(?TABLE_PROCESS, self()),
	Table = ets:new(?MODULE, Opts),
	Pid ! {table, Table},
	receive
		finish -> ok
	end,
	ok.

do(_, {_, []}) -> ok;
do(Action, {T,[X|Xs]}) ->
	ets:Action(T, X),
	do(Action, {T, Xs}).

insert({_, []}) -> ok;
insert({T,[X|Xs]}) ->
	%erlang:display(X),
	ets:insert(T, {X}),
	insert({T, Xs}).

setup([[insert, Table, P, Seed], _T, _K, _W, _R, _C, P, _S]) ->
	{{continue, ignore}, [delete, Table, 0, Seed]};
setup([[insert, Table, P, Seed], _T, K, W | _]) ->
	random:seed(Seed),
	WOps = round(math:pow(?BASE, W)),
	Init = fun(Idx, Max) ->
		R = WOps rem Max,
		C = if
			(Idx < R) -> 1; % TODO check this is correct
			true -> 0
		end,
		Amount = WOps div Max + C,
		Randoms = make_randoms(Amount, K),
		 {Table, Randoms}
	end,
	Workers = make_workers(Init, fun(X) -> insert(X) end),
	NextSeed = make_seed(),
	Name = lists:flatten(["insert ", integer_to_list(WOps)]),
	{{continue, ignore}, [run, insert, Name, Workers, Table, P, NextSeed]};
setup([[lookup, Table, P, Seed], _T, K, _W, R | _]) ->
	random:seed(Seed),
	ROps = round(math:pow(?BASE, R)),
	Init = fun(_Idx, Max) ->
		Amount = ROps div Max, % FIXME TODO THIS IS INEXACT
		Randoms = make_randoms(Amount, K),
		{Table, Randoms}
	end,
	
	Workers = make_workers(Init, fun(X) -> do(lookup, X) end),
	NextSeed = make_seed(),
	Name = lists:flatten(["lookup ", integer_to_list(ROps)]),
	{{continue, ignore}, [run, lookup, Name, Workers, Table, P, NextSeed]};
setup([[delete, Table, P, _Seed], _T, _K, _W, _R, _C, P, _S]) ->
	ets:delete(Table),
	?TABLE_PROCESS ! finish,
	{{done,ignore}, ok};
setup([[delete, Table, P, Seed], _T, K, W | _ ]) ->
	random:seed(Seed),
	WOps = round(math:pow(?BASE, W)),
	Init = fun(_Idx, Max) ->
		Amount = WOps div Max, % FIXME TODO THIS IS INEXACT
		Randoms = make_randoms(Amount, K),
		{Table, Randoms}
	end,
	
	Workers = make_workers(Init, fun(X) -> do(delete, X) end),
	NextSeed = make_seed(),
	Name = lists:flatten(["delete ", integer_to_list(WOps)]),
	{{continue, ignore}, [run, delete, Name, Workers, Table, P, NextSeed]}.

run_bench([insert | State]) ->
	run_insert(State);
run_bench([lookup | State]) ->
	run_lookup(State);
run_bench([delete | State]) ->
	run_delete(State).

run_insert([Name, Workers, Table, Part, Seed | _]) ->
	start(Workers),
	wait_for(Workers),
	{{continue, Name}, [lookup, Table, Part, Seed]}.

run_lookup([Name, Workers, Table, Part, Seed | _]) ->
	start(Workers),
	wait_for(Workers),
	{{continue, Name}, [insert, Table, Part+1, Seed]}.

run_delete([Name, Workers, Table, Part, Seed | _]) ->
	start(Workers),
	wait_for(Workers),
	{{continue, Name}, [delete, Table, Part+1, Seed]}.

make_workers(Init, Work) ->
	Schedulers = erlang:system_info(schedulers),
	Randoms = lists:map(fun make_seed/1, lists:seq(1, Schedulers)),
	make_workers(Init, Work, Randoms, 0, Schedulers, []).

make_workers(_I, _W, [], M, M, Agg) ->
	ready(Agg),
	Agg;
make_workers(Init, Work, [Seed|R], Cnt, Max, Agg) ->
	Coordinator = self(),
	Worker = spawn(fun() -> worker(Coordinator, Init, Work, Cnt, Max, Seed) end),
	make_workers(Init, Work, R, Cnt+1, Max, [Worker | Agg]).

worker(Coordinator, Init, Work, Cnt, Max, Seed) ->
	random:seed(Seed),
	InitState = Init(Cnt, Max),
	Coordinator ! {self(), ready},
	receive
		{NewCoordinator, start} -> ok % wait for signal from coordinator
	end,
	Work(InitState),
	NewCoordinator ! {self(), done},
	ok.


start([]) -> ok;
start([Worker|Workers]) ->
	Worker ! {self(), start},
	start(Workers).
wait_for(Ws) -> wait_for_signal(done, Ws).
ready(Ws) -> wait_for_signal(ready, Ws).

wait_for_signal(_, []) -> ok;
wait_for_signal(Signal, [Worker|Workers]) ->
	receive
		{Worker, Signal} -> wait_for_signal(Signal, Workers)
	end.

make_seed(_) -> make_seed().
make_seed() ->
	{
		random:uniform(?RAND_MAX),
		random:uniform(?RAND_MAX),
		random:uniform(?RAND_MAX)
	}.

make_randoms(Amnt, Range) -> make_randoms(Amnt, Range, []).
make_randoms(0, _, Acc) -> Acc;
make_randoms(Amnt, Range, Acc) ->
	make_randoms(Amnt-1, Range, [random:uniform(Range) | Acc]).
