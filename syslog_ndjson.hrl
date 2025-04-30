%% @doc This header file defines the syslog_entry record that represents BSD Syslog (RFC 5424) entries.

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
