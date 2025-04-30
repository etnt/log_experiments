-module(syslog_ndjson_example).
-export([to_file/2]).

-include("syslog_ndjson.hrl").

to_file(NumOfEntries, Filename) when is_integer(NumOfEntries) ->
    {ok, File} = file:open(Filename, [write, raw]),
    try
        lists:foreach(
            fun(I) -> write_entry(I, File) end, lists:seq(1, NumOfEntries)
        )
    after
        file:close(File)
    end.

write_entry(I, File) ->
    Record = #syslog_entry{
        priority = 13 rem I + 1,
        facility = I rem 10 + 1,
        severity = I rem 7,
        version = 1,
        timestamp = generate_timestamp(I),
        hostname = "myhost.example.com",
        app_name = "myapp",
        proc_id = integer_to_list(12345 + I),
        msg_id = "AUTHPRIV",
        structured_data = #{
            <<"exampleSDID@32473">> => #{
                <<"iut">> => <<"o=eff.org,ou=iETF,dc=example,cn=Jane Doe">>,
                <<"eventSource">> => <<"Application">>
            }
        },
        message =
            "Authentication failure for user 'john" ++ integer_to_list(I) ++ "'"
    },
    JsonString = syslog_ndjson:to_ndjson(Record),
    file:write(File, JsonString).

% Generate a timestamp that increments by 1 second for each entry
generate_timestamp(I) ->
    {{Year, Month, Day}, {Hour, Minute, Second}} = calendar:universal_time(),
    NewSecond = (Second + I) rem 60,
    NewMinute = Minute + (Second + I) div 60,
    NewHour = (Hour + NewMinute div 60) rem 24,
    NewDay = Day + (Hour + NewMinute div 60) div 24,
    % Simple formatting, could be improved with proper month boundaries
    lists:flatten(
        io_lib:format(
            "~4..0w-~2..0w-~2..0wT~2..0w:~2..0w:~2..0wZ",
            [Year, Month, NewDay, NewHour, NewMinute rem 60, NewSecond]
        )
    ).
