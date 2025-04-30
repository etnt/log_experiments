-module(otel_example).
-export([start/0, emit_metric/0, emit_trace/0]).

-include_lib("opentelemetry_api/include/opentelemetry.hrl").

%%
%% Assuming the opentelemtery-erlang library is cloned and built in a parallel directory.
%% First add the path to the ebin directories we will need:
%%
%%  for i in `find _build -name ebin -type d`; do echo "code:add_pathz(\"${PWD}/$i\")."; done >> ~/.erlang
%%
%% Then compile as:
%%
%% erlc -I ../opentelemetry-erlang/apps otel_example.erl
%%

start() ->
    % Ensure the necessary OpenTelemetry applications are started
    application:ensure_started(opentelemetry),
    application:ensure_started(otel_exporter_otlp),

    % Configuration for the OTLP exporter (adjust as needed)
    application:set_env(otel_exporter_otlp, endpoint, "http://hedlund:4317"),
    application:set_env(opentelemetry, service_name, "my-erlang-app"),

    ok.

emit_metric() ->
    Meter = opentelemetry:get_meter(<<"my_app_meter">>, <<"1.0.0">>),
    Counter = otel_meter:create_counter(Meter, <<"my_counter">>, #{
        description => <<"Example counter">>, unit => "{requests}"
    }),
    otel_counter:add(Counter, 1, #{<<"environment">> => <<"production">>}),
    io:format("Metric emitted: my_app_meter:my_counter incremented~n").

emit_trace() ->
    Ctx = otel_tracer:start_span(<<"my_operation">>, #{
        kind => ?SPAN_KIND_INTERNAL
    }),
    otel_span:set_attribute(<<"user.id">>, 123),
    % Simulate some work
    timer:sleep(100),
    otel_tracer:end_span(Ctx),
    io:format("Trace emitted: Span 'my_operation' finished~n").
