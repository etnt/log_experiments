-module(otel_sup).
-behaviour(supervisor).
-export([start_link/0]).
-export([init/1]).


start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
  {ok, { {one_for_one, 5, 10}, [
    {otel_collector,{otel_collector, start_link, []}, transient, 100, worker, [] },
    {otel_uploader, {otel_uploader, start_link, []}, transient, 100, worker, [] },
    {otel_stats, {otel_stats, start_link, []}, transient, 100, worker, [] }
  ]}}.
