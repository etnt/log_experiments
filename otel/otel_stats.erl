-module(otel_stats).
-export([start_link/0]).
-include_lib("kernel/include/logger.hrl").
-include_lib("corelib/include/corelib_openapi.hrl").

-export([init/1, handle_info/2, handle_call/3, terminate/2, get_stats/0, put_counters/1]).

% tests
-export([reset/0]).


start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec get_stats() -> opentelemetry_stats_map().
get_stats() ->
  gen_server:call(otel_stats, get_stats).

-spec put_counters(opentelemetry_stats_map()) -> {counters, opentelemetry_stats_map()}.
put_counters(#{} = Counters) ->
  otel_stats ! {counters, Counters}.

reset() ->
  gen_server:call(otel_stats, reset).

-record(stats, {
  counters = #{}
}).

init([]) ->
  {ok, #stats{}}.

handle_call(get_stats, _, #stats{counters = Counters} = State) ->
  {reply, Counters, State};

handle_call(reset, _, #stats{} = State) ->
  {reply, ok, State#stats{counters = #{}}}.

handle_info({counters, Counters}, #stats{counters = Counters0} = State) ->
  {noreply, State#stats{counters = accumulate_counters(Counters0, Counters)}};

handle_info(Msg, #stats{} = State) ->
  ?LOG_INFO(#{unknown_msg => Msg}),
  {noreply, State}.


terminate(_,_) ->
  ok.

-spec accumulate_counters(opentelemetry_stats_map(), opentelemetry_stats_map()) -> opentelemetry_stats_map().
accumulate_counters(#{} = InCounters, #{} = Counters) ->
  maps:fold(fun
    (K,V,Acc) -> Acc#{K => V + maps:get(K,Acc,0)}
  end, Counters, InCounters).


