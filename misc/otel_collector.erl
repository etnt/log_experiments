-module(otel_collector).
-include_lib("kernel/include/logger.hrl").
-include_lib("corelib/include/corelib_openapi.hrl").

-export([save_span/1, save_trace/1, read/1]).
-export([flush/0]).
-export([start_link/0]).
-export([init/1, handle_call/3, handle_info/2, terminate/2]).

% tests
-export([reset/0]).

save_span(#{spanId := _} = Span) ->
  gen_server:call(otel_collector, Span),
  ok.

save_trace(TraceId) ->
  gen_server:call(otel_collector, {save_trace, TraceId}),
  ok.

read(TraceId) ->
  Spans = [S || {_,T,S} <- ets:tab2list(otel_spans), T == TraceId],
  case Spans of
    [] -> undefined;
    _ -> #{spans => Spans}
  end.

-spec flush() -> opentelemetry_stats_map().
flush() ->
  {ok, URL, Spans} = gen_server:call(otel_collector, flush),
  case Spans of
    [_|_] when URL =/= undefined -> upload(URL, Spans);
    _ -> #{}
  end.

-spec upload(url(), list()) -> opentelemetry_stats_map().
upload(URL, Spans) ->
  Spans1 = lists:map(fun(#{attributes := A} = S) ->
    A1 = [#{key => K,value => case V of
      _ when is_binary(V) -> #{stringValue => V};
      _ when is_integer(V) -> #{intValue => V};
      _ when V == true; V == false -> #{boolValue => V};
      _ when is_atom(V) -> #{stringValue => atom_to_binary(V,latin1)};
      _ when is_number(V) -> #{doubleValue => V};
      _ -> #{stringValue => iolist_to_binary(io_lib:format("~p",V))}
    end} || {K,V} <- maps:to_list(A), V =/= undefined],
    S1 = S#{attributes => A1},
    S2 = case S1 of
      #{status := #{code := ok}} -> S1#{status => #{code => 1}};
      #{status := #{code := error} = St} -> S1#{status => St#{code => 2}};
      _ -> S1
    end,
    S3 = case S2 of
      #{kind := internal} -> S2#{kind => 1};
      #{kind := server} -> S2#{kind => 2};
      #{kind := client} -> S2#{kind => 3};
      #{kind := producer} -> S2#{kind => 4};
      #{kind := consumer} -> S2#{kind => 5};
      #{} -> S2#{kind => 1}
    end,
    S4 = S3#{
      traceId => maps:get(traceId,S3),
      spanId => maps:get(spanId,S3),
      parentSpanId => case maps:get(parentSpanId,S3,undefined) of
        undefined -> <<>>;
        PSpanId -> PSpanId
      end
    },
    S4
  end, Spans),
  Packet = #{
    resourceSpans => [#{
      resource => #{
        attributes => [
          #{key => <<"service.name">>, value => #{stringValue => otel:service_name()}},
          #{key => <<"service.instance.id">>, value => #{stringValue => corelib:instance_id()}},
          #{key => <<"host.name">>, value => #{stringValue => corelib:hostname()}},
          #{key => <<"service.version">>, value => #{stringValue => base:version(describe)}}
        ]
      },
      scopeSpans => [#{
        spans => Spans1
      }]
    }]
  },
  JSON = corejson:encode(Packet),
  % URL may be "http://localhost:4318/v1/traces"
  case lhttpc:request(URL, post, [{"Content-Type", "application/json"}], JSON, 5000) of
    {ok, {{Code,_}, _, Body}} ->
      Json =
        try json:decode(Body)
        catch _:_:_ ->
          ?LOG_DEBUG("Unable to decode json: ~p", [binary:part(Body, 0, min(byte_size(Body), 30))]),
          #{}
        end,
      Msg = maps:get(<<"message">>, Json, <<>>),
      ?LOG_DEBUG(#{code => Code, spans => length(Spans), response => Msg}),
      case Code of
        200 -> #{sent_count => length(Spans)};
        _ -> #{drop_network_count => length(Spans)}
      end;
    {error ,E} ->
      ?LOG_INFO(#{error => E}),
      #{drop_network_count => length(Spans)}
  end.

reset() ->
  gen_server:call(otel_collector, reset),
  reset_persistent_terms(),
  ets:delete_all_objects(otel_spans).

reset_persistent_terms() ->
  persistent_term:erase(otel_enabled),
  persistent_term:erase(otel_overloaded),
  persistent_term:erase(otel_sampling),
  persistent_term:erase(otel_service_name),
  persistent_term:erase(otel_duration_threshold).

start_link() ->
  gen_server:start_link({local,?MODULE}, ?MODULE, [], []).

-record(collector, {
  enabled = false,
  overloaded = false,
  url,
  sampling,
  duration_threshold,

  span_count = 0,
  rate_limit,
  limit_timer
}).


init([]) ->
  ets:new(otel_spans, [public,named_table]),
  LimitTimer = erlang:send_after(1000, self(), flush_limit_timer),
  Collector = #collector{
    limit_timer = LimitTimer
  },
  {ok, Collector}.

read_url(undefined, Collector) ->
  Collector#collector{
    url = undefined
  };

read_url(FullURL, Collector) ->
  Q = uri_string:parse(iolist_to_binary(FullURL)),
  Query = maps:get(query, Q, <<>>),
  URL = uri_string:recompose(maps:remove(query,Q)),
  Params = uri_string:dissect_query(Query),
  RateLimit = case proplists:get_value(<<"rate_limit">>, Params) of
    undefined -> undefined;
    RL -> binary_to_integer(RL)
  end,
  Sampling = case proplists:get_value(<<"sampling">>, Params) of
    undefined -> undefined;
    SL -> binary_to_integer(SL)
  end,
  DurationThreshold = case proplists:get_value(<<"duration_threshold">>, Params) of
    undefined -> undefined;
    DT -> binary_to_integer(DT)
  end,
  persistent_term:put(otel_sampling, Sampling),
  persistent_term:put(otel_duration_threshold, Sampling),
  ServiceName = proplists:get_value(<<"service_name">>, Params, <<"streamer">>),
  persistent_term:put(otel_service_name, ServiceName),
  Collector#collector{
    url = URL,
    rate_limit = RateLimit,
    sampling = Sampling,
    duration_threshold = DurationThreshold
  }.

handle_call(update, _, #collector{} = Collector0) ->
  URL = application:get_env(corelib, opentelemetry_url, undefined),
  Collector1 = read_url(URL, Collector0),
  Collector = set_enabled_flag(Collector1),
  {reply, ok, Collector#collector{span_count = 0}};

handle_call(flush, _, #collector{url = URL} = Collector) ->
  Spans = [S || {_,_,S} <- ets:tab2list(otel_spans)],
  ets:delete_all_objects(otel_spans),
  {reply, {ok, URL, Spans}, Collector};

handle_call({save_trace, _TraceId}, _, #collector{} = Collector) ->
  {reply, ok, Collector};

handle_call(#{spanId := _} = Span, _, #collector{} = Collector) ->
  Collector1 = save_span1(Span, Collector),
  {reply, ok, Collector1};

handle_call(reset, _, #collector{limit_timer = Timer}) ->
  {reply, ok, #collector{limit_timer = Timer}}.

handle_info(flush_limit_timer, #collector{limit_timer = OldTimer} = Collector) ->
  is_reference(OldTimer) andalso erlang:cancel_timer(OldTimer),
  T = erlang:system_time(milli_seconds),
  T1 = (T div 1000)*1000 + 1500 - T, % Считаем время до середины следующей секунды
  LimitTimer = erlang:send_after(T1, self(), flush_limit_timer),
  {noreply, set_enabled_flag(Collector#collector{limit_timer = LimitTimer, span_count = 0})};

handle_info(#{spanId := _} = Span, #collector{} = Collector) ->
  Collector1 = save_span1(Span, Collector),
  {noreply, Collector1}.


set_enabled_flag(#collector{url = URL, enabled = Enabled, overloaded = Overloaded} = Collector) ->
  RateLimit = Collector#collector.rate_limit,
  SpanCount = Collector#collector.span_count,
  RateLimitExhausted = is_integer(RateLimit) andalso SpanCount >= RateLimit,

  case RateLimitExhausted of
    Overloaded -> ok;
    _ -> persistent_term:put(otel_overloaded, RateLimitExhausted)
  end,

  NewEnabled = URL =/= undefined,
  case NewEnabled of
    Enabled -> ok;
    _ -> persistent_term:put(otel_enabled, NewEnabled)
  end,
  Collector#collector{enabled = NewEnabled, overloaded = RateLimitExhausted}.


save_span1(#{spanId := SpanId, traceId := TraceId} = Span, #collector{span_count = SC} = Collector) ->
  ets:insert(otel_spans, {SpanId, TraceId, Span}),
  Collector1 = set_enabled_flag(Collector#collector{span_count = SC+1}),
  Collector1.


terminate(_,_) ->
  ok.
