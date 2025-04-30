-module(syslog_ndjson_validation_test).

-export([run/0, test_valid/0, test_invalid/0]).

-include("syslog_ndjson.hrl").

%% @doc Run all validation tests and print results
run() ->
    io:format("Running validation tests...~n"),
    test_valid(),
    test_invalid(),
    io:format("All tests completed.~n").

%% @doc Test valid syslog entries
test_valid() ->
    % Create a valid syslog entry
    ValidEntry = #syslog_entry{
        priority = 13,
        facility = 1,
        severity = 5,
        version = 1,
        % Added milliseconds
        timestamp = "2023-10-27T10:00:00.000Z",
        hostname = "myhost.example.com",
        app_name = "myapp",
        proc_id = "12345",
        msg_id = "AUTHPRIV",
        structured_data = #{
            <<"exampleSDID@32473">> => #{
                <<"iut">> => <<"o=eff.org,ou=iETF,dc=example,cn=Jane Doe">>,
                <<"eventSource">> => <<"Application">>
            }
        },
        message = "Authentication failure for user 'john'"
    },

    % Validate the entry
    Result = syslog_ndjson_validator:validate(ValidEntry),
    io:format("Valid entry validation result: ~p~n", [Result]),

    % Test with null values (should pass in non-strict mode)
    NullableEntry = ValidEntry#syslog_entry{
        hostname = null,
        app_name = null,
        proc_id = null,
        msg_id = null,
        structured_data = null,
        message = null
    },

    NullResult = syslog_ndjson_validator:validate(NullableEntry),
    io:format("Nullable entry validation result: ~p~n", [NullResult]),

    StrictNullResult = syslog_ndjson_validator:validate_strict(NullableEntry),
    io:format("Strict nullable entry validation result: ~p~n", [
        StrictNullResult
    ]).

%% @doc Test invalid syslog entries
test_invalid() ->
    % Create an invalid syslog entry (wrong version)
    InvalidVersion = #syslog_entry{
        priority = 13,
        facility = 1,
        severity = 5,
        % Invalid - should be 1
        version = 2,
        % Added milliseconds
        timestamp = "2023-10-27T10:00:00.000Z",
        hostname = "myhost.example.com",
        app_name = "myapp",
        proc_id = "12345",
        msg_id = "AUTHPRIV",
        structured_data = #{},
        message = "Authentication failure"
    },

    % Validate the entry
    VersionResult = syslog_ndjson_validator:validate(InvalidVersion),
    io:format("Invalid version validation result: ~p~n", [VersionResult]),

    % Invalid timestamp format
    InvalidTimestamp = #syslog_entry{
        priority = 13,
        facility = 1,
        severity = 5,
        version = 1,
        % Invalid format

        % Keep this invalid for testing
        timestamp = "2023/10/27 10:00:00",
        hostname = "myhost.example.com",
        app_name = "myapp",
        proc_id = "12345",
        msg_id = "AUTHPRIV",
        structured_data = #{},
        message = "Authentication failure"
    },

    TimestampResult = syslog_ndjson_validator:validate(InvalidTimestamp),
    io:format("Invalid timestamp validation result: ~p~n", [TimestampResult]),

    % Test exceeding max length

    % Should be max 48 chars
    LongAppName = list_to_binary(string:chars($a, 60)),
    InvalidLengthEntry = #syslog_entry{
        priority = 13,
        facility = 1,
        severity = 5,
        version = 1,
        % Added milliseconds
        timestamp = "2023-10-27T10:00:00.000Z",
        hostname = "myhost.example.com",
        app_name = LongAppName,
        proc_id = "12345",
        msg_id = "AUTHPRIV",
        structured_data = #{},
        message = "Authentication failure"
    },

    LengthResult = syslog_ndjson_validator:validate(InvalidLengthEntry),
    io:format("Invalid length validation result: ~p~n", [LengthResult]),

    % Test invalid structured data
    InvalidStructuredData = #syslog_entry{
        priority = 13,
        facility = 1,
        severity = 5,
        version = 1,
        % Added milliseconds
        timestamp = "2023-10-27T10:00:00.000Z",
        hostname = "myhost.example.com",
        app_name = "myapp",
        proc_id = "12345",
        msg_id = "AUTHPRIV",
        structured_data = #{
            <<"valid">> => #{
                <<"valid_key">> => <<"valid_value">>
            },
            % Invalid key type
            123 => #{
                <<"key">> => <<"value">>
            }
        },
        message = "Authentication failure"
    },

    StructuredResult = syslog_ndjson_validator:validate(InvalidStructuredData),
    io:format("Invalid structured data validation result: ~p~n", [
        StructuredResult
    ]).
