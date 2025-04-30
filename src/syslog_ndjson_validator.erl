-module(syslog_ndjson_validator).

-export([validate/1, validate_strict/1]).

-include("syslog_ndjson.hrl").

%% @doc Validates a syslog_entry record against the OpenAPI schema
%% Returns ok if valid, or {error, [Reasons]} with a list of validation errors
-spec validate(syslog_record()) -> ok | {error, [binary()]}.
validate(Record) ->
    Errors = validate_entry(Record, false),
    case Errors of
        [] -> ok;
        _ -> {error, Errors}
    end.

%% @doc Validates a syslog_entry record strictly against the OpenAPI schema
%% In strict mode, nullable fields that are null will still be validated for their format
%% Returns ok if valid, or {error, [Reasons]} with a list of validation errors
-spec validate_strict(syslog_record()) -> ok | {error, [binary()]}.
validate_strict(Record) ->
    Errors = validate_entry(Record, true),
    case Errors of
        [] -> ok;
        _ -> {error, Errors}
    end.

%% @private Validates individual fields of the syslog entry
%% Returns a list of error messages, empty list means valid
-spec validate_entry(syslog_record(), boolean()) -> [binary()].
validate_entry(
    #syslog_entry{
        priority = P,
        facility = F,
        severity = S,
        version = V,
        timestamp = TS,
        % Not used directly but included for pattern matching
        hostname = _HN,
        app_name = AN,
        proc_id = PID,
        msg_id = MID,
        structured_data = SD,
        message = M
    },
    StrictMode
) ->
    [
        % Integer validations
        validate_integer("priority", P),
        validate_integer("facility", F),
        validate_integer("severity", S),
        validate_integer_value(
            "version", V, 1, "For RFC 5424, version should be 1"
        ),

        % String validations with null handling
        validate_timestamp("timestamp", TS, StrictMode),
        validate_string_length("app_name", AN, 48, StrictMode),
        validate_string_length("proc_id", PID, 128, StrictMode),
        validate_string_length("msg_id", MID, 32, StrictMode),

        % Structured data validation
        validate_structured_data("structured_data", SD, StrictMode),

        % Message can be any string or null, no validation needed beyond type
        validate_maybe_string("message", M)
        % Remove all "ok" results, leaving only errors
    ] -- [ok].

%% @private Validates that a field is an integer
-spec validate_integer(string(), any()) -> ok | binary().
validate_integer(_Field, Value) when is_integer(Value) -> ok;
validate_integer(Field, Value) ->
    list_to_binary(
        io_lib:format("~s must be an integer, got: ~p", [Field, Value])
    ).

%% @private Validates that an integer field has a specific value
-spec validate_integer_value(string(), any(), integer(), string()) ->
    ok | binary().
validate_integer_value(_Field, Value, ExpectedValue, _Reason) when
    is_integer(Value), Value =:= ExpectedValue
->
    ok;
validate_integer_value(Field, Value, ExpectedValue, Reason) when
    is_integer(Value)
->
    list_to_binary(
        io_lib:format("~s should be ~p: ~s", [Field, ExpectedValue, Reason])
    );
validate_integer_value(Field, Value, _, _) ->
    validate_integer(Field, Value).

%% @private Validates an RFC 3339 timestamp string
-spec validate_timestamp(string(), any(), boolean()) -> ok | binary().
% nullable field in non-strict mode
validate_timestamp(_, null, false) ->
    ok;
validate_timestamp(Field, null, true) ->
    list_to_binary(
        io_lib:format("~s is null but required in strict validation", [Field])
    );
validate_timestamp(Field, Value, _) when
    not is_list(Value) andalso not is_binary(Value)
->
    list_to_binary(
        io_lib:format("~s must be a string, got: ~p", [Field, Value])
    );
validate_timestamp(Field, Value, _) ->
    % Pattern for RFC 3339 timestamp validation (YYYY-MM-DDTHH:MM:SS[.fraction]Z)
    Pattern = "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?Z$",
    ValueStr =
        if
            is_binary(Value) -> binary_to_list(Value);
            true -> Value
        end,
    case re:run(ValueStr, Pattern, [{capture, none}]) of
        match ->
            % Further validate by trying to parse the timestamp
            try
                % Ignoring the Time variable to avoid warning
                {date, _} = httpd_util:convert_request_date(ValueStr),
                ok
            catch
                _:_ ->
                    list_to_binary(
                        io_lib:format("~s has invalid date format: ~s", [
                            Field, ValueStr
                        ])
                    )
            end;
        nomatch ->
            list_to_binary(
                io_lib:format("~s doesn't match ISO 8601/RFC 3339 format: ~s", [
                    Field, ValueStr
                ])
            )
    end.

%% @private Validates a string field with maximum length
-spec validate_string_length(string(), any(), integer(), boolean()) ->
    ok | binary().
% nullable field in non-strict mode
validate_string_length(_, null, _, false) ->
    ok;
validate_string_length(Field, null, _, true) ->
    list_to_binary(
        io_lib:format("~s is null but required in strict validation", [Field])
    );
validate_string_length(Field, Value, _MaxLen, _) when
    not is_list(Value) andalso not is_binary(Value)
->
    list_to_binary(
        io_lib:format("~s must be a string, got: ~p", [Field, Value])
    );
validate_string_length(Field, Value, MaxLength, _) ->
    Length =
        if
            is_binary(Value) -> byte_size(Value);
            true -> length(Value)
        end,
    if
        Length =< MaxLength ->
            ok;
        true ->
            list_to_binary(
                io_lib:format("~s exceeds maximum length of ~p", [
                    Field, MaxLength
                ])
            )
    end.

%% @private Validates that a field is a string or null
-spec validate_maybe_string(string(), any()) -> ok | binary().
validate_maybe_string(_, null) ->
    ok;
validate_maybe_string(_Field, Value) when is_list(Value); is_binary(Value) ->
    ok;
validate_maybe_string(Field, Value) ->
    list_to_binary(
        io_lib:format("~s must be a string or null, got: ~p", [Field, Value])
    ).

%% @private Validates the structured data field
-spec validate_structured_data(string(), any(), boolean()) -> ok | binary().
% nullable field in non-strict mode
validate_structured_data(_, null, false) ->
    ok;
validate_structured_data(Field, null, true) ->
    list_to_binary(
        io_lib:format("~s is null but required in strict validation", [Field])
    );
validate_structured_data(Field, Value, _) when not is_map(Value) ->
    list_to_binary(io_lib:format("~s must be a map, got: ~p", [Field, Value]));
validate_structured_data(_, Value, _) when is_map(Value) ->
    % Check that all keys are strings and all values are maps
    Errors = maps:fold(
        fun(K, V, Acc) ->
            KeyError =
                if
                    not (is_list(K) orelse is_binary(K)) ->
                        [
                            list_to_binary(
                                io_lib:format(
                                    "structured_data key must be a string, got: ~p",
                                    [K]
                                )
                            )
                        ];
                    true ->
                        []
                end,

            ValueErrors =
                if
                    not is_map(V) ->
                        [
                            list_to_binary(
                                io_lib:format(
                                    "structured_data value for ~p must be a map, got: ~p",
                                    [K, V]
                                )
                            )
                        ];
                    true ->
                        % Check that all values in the nested map are strings
                        maps:fold(
                            fun(NK, NV, NAcc) ->
                                if
                                    not (is_list(NK) orelse is_binary(NK)) ->
                                        [
                                            list_to_binary(
                                                io_lib:format(
                                                    "structured_data nested key must be a string, got: ~p",
                                                    [NK]
                                                )
                                            )
                                            | NAcc
                                        ];
                                    not (is_list(NV) orelse is_binary(NV)) ->
                                        [
                                            list_to_binary(
                                                io_lib:format(
                                                    "structured_data nested value must be a string, got: ~p",
                                                    [NV]
                                                )
                                            )
                                            | NAcc
                                        ];
                                    true ->
                                        NAcc
                                end
                            end,
                            [],
                            V
                        )
                end,

            KeyError ++ ValueErrors ++ Acc
        end,
        [],
        Value
    ),

    case Errors of
        [] ->
            ok;
        _ ->
            list_to_binary(
                io_lib:format("structured_data validation errors: ~p", [Errors])
            )
    end.
