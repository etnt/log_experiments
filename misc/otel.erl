-module(otel).
%%
%% https://gist.github.com/maxlapshin/bafa13a0f17810a69dd893100da57be7
%% See also thread at the Erlang Forum.
%%
-include_lib("kernel/include/logger.hrl").
-include_lib("corelib/include/corelib_openapi.hrl").

-export([start_trace/0, start_trace/1]).
-export([end_trace/0]).
-export([start_span/0, start_span/1]).
-export([end_span/0, end_span/1]).
-export([setattrs/1, setname/1]).
-export([get_context/0, set_context/1]).
-export([clear_context/0]).
-export([traceparent/0]).
-export([lhttpc_header/0]).
-export([get_stats/0]).
-export([load_config/1]).
-export([is_enabled/0, is_overloaded/0]).
-export([sampling_allows/0, duration_threshold/0, service_name/0]).
-export([get_trace/1]).

% tests
-export([reset/0]).


% https://www.w3.org/TR/trace-context/#version-format
-define(TRACEPARENT_VERSION, "00").

% https://github.com/open-telemetry/opentelemetry-proto/blob/main/opentelemetry/proto/collector/trace/v1/trace_service.proto
% https://github.com/open-telemetry/opentelemetry-proto/blob/main/opentelemetry/proto/trace/v1/trace.proto

-type trace_id() :: binary().
-type span_id() :: binary().
-type span_kind() :: server | client | producer | consumer | internal.


load_config(#{} = Env) ->
  EnvURL = application:get_env(corelib, env_opentelemetry_url, undefined),
  ConfigURL = maps:get(opentelemetry_url, Env, undefined),

  NewURL = case {ConfigURL, EnvURL} of
    {undefined, EnvURL} when is_binary(EnvURL) ->
      ?LOG_INFO("Environment opentelemetry url is used: ~p", [EnvURL]),
      EnvURL;
    _ ->
      ConfigURL
  end,

  CurrentURL = application:get_env(corelib, opentelemetry_url, undefined),
  case CurrentURL of
    NewURL ->
      do_nothing;
    _ ->
      application:set_env(corelib, opentelemetry_url, NewURL),
      gen_server:call(otel_collector, update),
      otel_stats:reset()
  end,
  ok.

is_enabled() ->
  persistent_term:get(otel_enabled, false).

is_overloaded() ->
  persistent_term:get(otel_overloaded, false).

service_name() ->
  persistent_term:get(otel_service_name, <<"streamer">>).

sampling_allows() ->
  case persistent_term:get(otel_sampling, undefined) of
    undefined ->
      true;
    SamplingPercent ->
      rand:uniform(100) =< SamplingPercent
  end.

duration_threshold() ->
  persistent_term:get(otel_duration_threshold, undefined).

-spec start_trace() -> trace_id() | false.
start_trace() ->
  Enabled = is_enabled(),
  Overloaded = is_overloaded(),
  SamplingAllows = sampling_allows(),
  Ready = Enabled andalso not Overloaded andalso SamplingAllows,
  case Ready of
    true ->
      T = erlang:system_time(seconds),
      TraceId = hexify:hex(<<T:32, (rand:uniform(1 bsl 32)):32, (rand:uniform(1 bsl 32)):32, (rand:uniform(1 bsl 32)):32>>),
      put('$otel_trace_id', TraceId),
      put('$otel_span', []),
      TraceId;
    false ->
      Counter = case {Overloaded, SamplingAllows} of
        {true, _} -> #{drop_overload_count => 1};
        {_, false} -> #{drop_sampling_count => 1};
        _ -> #{}
      end,
      otel_stats:put_counters(Counter),
      false
  end.

-spec start_trace(binary()) -> trace_id() | false.
start_trace(<<?TRACEPARENT_VERSION, "-",TraceParent/binary>>) ->
  case is_enabled() of
    true ->
      case binary:split(TraceParent, <<"-">>, [global]) of
        [TraceId, ParentSpanId | _] ->
          set_context([#{traceId => TraceId, spanId => ParentSpanId}]),
          TraceId;
        _ ->
          start_trace()
      end;
    false ->
      false
  end;

start_trace(undefined) ->
  start_trace().



-spec end_trace() -> ok.
end_trace() ->
  case get('$otel_trace_id') of
    undefined ->
      ok;
    TraceId ->
      otel_collector:save_trace(TraceId)
  end,
  clear_context(),
  ok.

-spec start_span() -> span_id() | false.
start_span() ->
  start_span(#{}).

% #{kind => .., name => ..}
-spec start_span(#{kind => span_kind(), name => binary(), attributes => #{_ => _}}) -> span_id() | false.
start_span(#{} = Span) ->
  case get('$otel_trace_id') of
    undefined ->
      false;
    TraceId ->
      T = erlang:system_time(micro_seconds),
      SpanId = hexify:hex(<<(T div 1000000):32, (T rem 1000000):32>>),
      Spans = get('$otel_span'),
      ParentSpanId = case Spans of
        [#{spanId := PSI}|_] -> PSI;
        [] -> undefined
      end,
      Span1 = Span#{
        startTimeUnixNano => erlang:system_time(nano_seconds),
        spanId => SpanId,
        parentSpanId => ParentSpanId,
        attributes => maps:get(attributes, Span, #{}),
        traceId => TraceId
      },
      put('$otel_span', [Span1|Spans]),
      SpanId
  end.

traceparent() ->
  case get('$otel_span') of
    [#{spanId := SpanId, traceId := TraceId}|_] ->
      <<"00-",TraceId/binary,"-",SpanId/binary,"-01">>;
    _ ->
      undefined
  end.

lhttpc_header() ->
  case traceparent() of
    undefined -> [];
    Traceparent -> [{"Traceparent", binary_to_list(Traceparent)}]
  end.

get_context() ->
  case get('$otel_span') of
    [#{spanId := _SpanId, traceId := _TraceId}|_] = Context ->
      Context;
    _ ->
      undefined
  end.

set_context([#{traceId := TraceId, spanId := _}|_] = Context) ->
  put('$otel_trace_id', TraceId),
  put('$otel_span', Context);

set_context(undefined) ->
  ok.

clear_context() ->
  erase('$otel_trace_id'),
  erase('$otel_span'),
  ok.

end_span() ->
  end_span(undefined).

end_span(Status) ->
  case get('$otel_span') of
    [CurrentSpan|Spans] ->
      Span1 = CurrentSpan#{
        endTimeUnixNano => erlang:system_time(nano_seconds)
      },
      Span2 = case Status of
        undefined -> Span1#{status => #{}};
        ok -> Span1#{status => #{code => ok}};
        _ when is_binary(Status) -> Span1#{status => #{code => error, message => Status}};
        _ -> Span1#{status => #{code => error, message => iolist_to_binary(io_lib:format("~p",[Status]))}}
      end,
      otel_collector:save_span(Span2),
      put('$otel_span', Spans),
      ok;
    _ ->
      ok
  end.


setattrs(#{} = NewAttrs) ->
  case get('$otel_span') of
    undefined ->
      false;
    [#{attributes := Attrs} = Span|Spans] ->
      NewAttrs2 = maps:fold(fun(K,V,Acc) ->
        K1 = case K of
          _ when is_binary(K) -> K;
          _ when is_atom(K) -> atom_to_binary(K,latin1)
        end,
        V1 = case V of
          _ when is_binary(V) -> V;
          [L|_] when is_integer(L) -> iolist_to_binary(V);
          _ when is_number(V) -> V;
          _ when V == true; V == false -> V;
          _ when is_atom(V) -> atom_to_binary(V,latin1)
        end,
        Acc#{K1 => V1}
      end, #{}, NewAttrs),
      Attrs2 = maps:merge(Attrs, NewAttrs2),
      Span1 = Span#{attributes => Attrs2},
      put('$otel_span', [Span1|Spans])
  end.

setname(Name) ->
  case get('$otel_span') of
    [#{} = Span|Spans] ->
      put('$otel_span', [Span#{name => Name}|Spans]),
      ok;
    _ ->
      false
  end.

get_trace(TraceId) ->
  otel_collector:read(TraceId).

-spec get_stats() -> opentelemetry_stats_map().
get_stats() ->
  otel_stats:get_stats().

reset() ->
  otel_collector:reset(),
  otel_stats:reset().
