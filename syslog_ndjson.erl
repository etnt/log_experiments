-module(syslog_ndjson).
%% @doc This module provides functionality to convert Erlang records
%% representing BSD Syslog (RFC 5424) entries into NDJSON format,
%% according to the OpenAPI specification provided earlier.
%%
%% The module defines a record `syslog_entry` that mirrors the schema
%% in the OpenAPI specification. The main function `to_ndjson/1` takes
%% an instance of this record and returns its JSON representation
%% as a single line, suitable for NDJSON output.
%%
%% **Example:**
%%
%% ```erlang
%% 1> Record = #syslog_entry{
%% 1>     priority = 13,
%% 1>     facility = 1,
%% 1>     severity = 5,
%% 1>     version = 1,
%% 1>     timestamp = "2023-10-27T10:00:00Z",
%% 1>     hostname = "myhost.example.com",
%% 1>     app_name = "myapp",
%% 1>     proc_id = "12345",
%% 1>     msg_id = "AUTHPRIV",
%% 1>     structured_data = #{
%% 1>         "exampleSDID@32473" => #{
%% 1>             "iut" => "o=eff.org,ou=iETF,dc=example,cn=Jane Doe",
%% 1>             "eventSource" => "Application"
%% 1>         }
%% 1>     },
%% 1>     message = "Authentication failure for user 'john'"
%% 1> };
%% {syslog_entry,13,1,5,1,"2023-10-27T10:00:00Z",
%%                 "myhost.example.com","myapp","12345","AUTHPRIV",
%%                 #{<<"exampleSDID@32473">> =>
%%                       #{<<"eventSource">> =>
%%                             <<"Application">>,
%%                         <<"iut">> =>
%%                             <<"o=eff.org,ou=iETF,dc=example,cn=Jane Doe">>}},
%%                 "Authentication failure for user 'john'"}
%% 2> syslog_ndjson_producer:to_ndjson(Record).
%% "{\"priority\":13,\"facility\":1,\"severity\":5,\"version\":1,\"timestamp\":\"2023-10-27T10:00:00Z\",\"hostname\":\"myhost.example.com\",\"app_name\":\"myapp\",\"proc_id\":\"12345\",\"msg_id\":\"AUTHPRIV\",\"structured_data\":{\"exampleSDID@32473\":{\"iut\":\"o=eff.org,ou=iETF,dc=example,cn=Jane Doe\",\"eventSource\":\"Application\"}},\"message\":\"Authentication failure for user 'john'\"}\n"
%% ```
-export([to_ndjson/1]).

-record(syslog_entry, {
    priority :: integer(),
    facility :: integer(),
    severity :: integer(),
    version :: integer(),
    timestamp :: string(),
    hostname :: maybe_string(),
    app_name :: maybe_string(),
    proc_id :: maybe_string(),
    msg_id :: maybe_string(),
    structured_data :: maybe_structured_data(),
    message :: maybe_string()
}).

-type maybe_string() :: string() | null.
-type structured_data_value() :: map().
-type maybe_structured_data() :: #{string() => structured_data_value()} | null.
-type syslog_record() :: #syslog_entry{}.

%% @doc Converts a syslog record to NDJSON format (single line JSON with newline)
-spec to_ndjson(syslog_record()) -> binary().
to_ndjson(SyslogRecord) ->
    JsonBin = json:encode(to_json_map(SyslogRecord)),
    % Convert binary to list, then append newline and convert back to binary
    list_to_binary([JsonBin, "\n"]).

%% @doc Converts a syslog record to a map suitable for JSON encoding
-spec to_json_map(syslog_record()) -> map().
to_json_map(#syslog_entry{
    priority = P,
    facility = F,
    severity = S,
    version = V,
    timestamp = TS,
    hostname = HN,
    app_name = AN,
    proc_id = PID,
    msg_id = MID,
    structured_data = SD,
    message = M
}) ->
    #{
        <<"priority">> => P,
        <<"facility">> => F,
        <<"severity">> => S,
        <<"version">> => V,
        <<"timestamp">> => maybe_null_to_erlang_null(TS),
        <<"hostname">> => maybe_null_to_erlang_null(HN),
        <<"app_name">> => maybe_null_to_erlang_null(AN),
        <<"proc_id">> => maybe_null_to_erlang_null(PID),
        <<"msg_id">> => maybe_null_to_erlang_null(MID),
        <<"structured_data">> => maybe_null_to_erlang_null(SD),
        <<"message">> => maybe_null_to_erlang_null(M)
    }.

%% @doc Handles null values and ensures strings are binary, maps are processed recursively
%% Also ensures map keys are binary for proper JSON encoding
-spec maybe_null_to_erlang_null(null | string() | binary() | map()) ->
    null | binary() | map().
maybe_null_to_erlang_null(null) ->
    null;
maybe_null_to_erlang_null(Map) when is_map(Map) ->
    % Convert map keys to binary and process values recursively
    maps:fold(
        fun(K, V, Acc) ->
            BinaryKey = to_binary(K),
            Acc#{BinaryKey => maybe_null_to_erlang_null(V)}
        end,
        #{},
        Map
    );
maybe_null_to_erlang_null(String) when is_binary(String) ->
    unicode:characters_to_binary(String);
maybe_null_to_erlang_null(String) when is_list(String) ->
    unicode:characters_to_binary(String).

%% @doc Helper function to convert keys to binary
-spec to_binary(string() | binary() | atom()) -> binary().
to_binary(X) when is_binary(X) -> X;
to_binary(X) when is_list(X) -> unicode:characters_to_binary(X);
to_binary(X) when is_atom(X) -> atom_to_binary(X, utf8).

%%% Example Usage (not part of the module, for demonstration)
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

example_syslog_record() ->
    #syslog_entry{
        priority = 13,
        facility = 1,
        severity = 5,
        version = 1,
        timestamp = "2023-10-27T10:00:00Z",
        hostname = "myhost.example.com",
        app_name = "myapp",
        proc_id = "12345",
        msg_id = "AUTHPRIV",
        structured_data = #{
            "exampleSDID@32473" => #{
                "iut" => "o=eff.org,ou=iETF,dc=example,cn=Jane Doe",
                "eventSource" => "Application"
            }
        },
        message = "Authentication failure for user 'john'"
    }.

example_syslog_record_nulls() ->
    #syslog_entry{
        priority = 165,
        facility = 20,
        severity = 5,
        version = 1,
        timestamp = "2023-10-27T10:05:00Z",
        hostname = null,
        app_name = null,
        proc_id = null,
        msg_id = null,
        structured_data = null,
        message = "User 'guest' accessed /index.html"
    }.

ndjson_generation_test() ->
    Record1 = example_syslog_record(),
    Result1 = to_ndjson(Record1),
    % Parse both expected and actual results into maps for comparison
    JsonResult1 = parse_json_remove_newline(Result1),
    ExpectedMap1 = #{
        <<"priority">> => 13,
        <<"facility">> => 1,
        <<"severity">> => 5,
        <<"version">> => 1,
        <<"timestamp">> => <<"2023-10-27T10:00:00Z">>,
        <<"hostname">> => <<"myhost.example.com">>,
        <<"app_name">> => <<"myapp">>,
        <<"proc_id">> => <<"12345">>,
        <<"msg_id">> => <<"AUTHPRIV">>,
        <<"structured_data">> => #{
            <<"exampleSDID@32473">> => #{
                <<"iut">> => <<"o=eff.org,ou=iETF,dc=example,cn=Jane Doe">>,
                <<"eventSource">> => <<"Application">>
            }
        },
        <<"message">> => <<"Authentication failure for user 'john'">>
    },
    ?assertEqual(ExpectedMap1, JsonResult1),

    Record2 = example_syslog_record_nulls(),
    Result2 = to_ndjson(Record2),
    JsonResult2 = parse_json_remove_newline(Result2),
    ExpectedMap2 = #{
        <<"priority">> => 165,
        <<"facility">> => 20,
        <<"severity">> => 5,
        <<"version">> => 1,
        <<"timestamp">> => <<"2023-10-27T10:05:00Z">>,
        <<"hostname">> => null,
        <<"app_name">> => null,
        <<"proc_id">> => null,
        <<"msg_id">> => null,
        <<"structured_data">> => null,
        <<"message">> => <<"User 'guest' accessed /index.html">>
    },
    ?assertEqual(ExpectedMap2, JsonResult2).

%% @doc Parse JSON string and remove trailing newline
parse_json_remove_newline(JsonBin) ->
    % Remove the trailing newline
    TrimmedBin = binary:part(JsonBin, 0, byte_size(JsonBin) - 1),
    % Parse the JSON into a map
    json:decode(TrimmedBin).

-endif.
