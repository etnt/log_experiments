-module(otel_uploader).
-export([start_link/0]).
-include_lib("kernel/include/logger.hrl").

-define(TIMEOUT, 5000).

-export([init/1, handle_info/2, handle_call/3, terminate/2]).

% tests
-export([flush/0]).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

flush() ->
  gen_server:call(otel_uploader, flush).

-record(uploader, {
  timer
}).

init([]) ->
  T = erlang:send_after(?TIMEOUT, self(), flush),
  {ok, #uploader{timer = T}}.

handle_call(flush, _, #uploader{} = Uploader0) ->
  {noreply, Uploader} = handle_info(flush, Uploader0),
  {reply, ok, Uploader}.

handle_info(flush, #uploader{timer = T0} = Uploader) ->
  erlang:cancel_timer(T0),
  Counters = otel_collector:flush(),
  otel_stats:put_counters(Counters),
  T = erlang:send_after(?TIMEOUT, self(), flush),
  {noreply, Uploader#uploader{timer = T}};

handle_info(Msg, #uploader{} = Uploader) ->
  ?LOG_INFO(#{unknown_msg => Msg}),
  {noreply, Uploader}.

terminate(_,_) ->
  ok.
