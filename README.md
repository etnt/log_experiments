# Syslog NDJSON

This project provides Erlang modules for working with BSD Syslog (RFC 5424) entries in NDJSON format. It allows for easy conversion between Erlang records and JSON representations of syslog entries, as well as validation against an OpenAPI specification.

## Overview

The Syslog NDJSON project consists of:

- **syslog_ndjson.erl**: Core module for converting syslog entries to NDJSON format
- **syslog_ndjson_validator.erl**: Module for validating syslog entries against the OpenAPI schema
- **syslog_ndjson.hrl**: Header file with record definitions
- **syslog_ndjson.yaml**: OpenAPI specification for the syslog entry format

This project is useful for applications that need to produce or consume syslog messages in a structured JSON format, particularly for logging pipelines, monitoring systems, and observability tools.

## Features

- Convert Erlang syslog records to NDJSON format
- Validate syslog entries against OpenAPI specification
- Handle RFC 5424 compliant syslog messages
- Support for structured data elements
- Proper handling of null values


## Usage Examples

### Converting a Syslog Entry to NDJSON

```erlang
% Include the header file with record definitions
-include_lib("log_experiments/include/syslog_ndjson.hrl").

% Create a syslog record
SyslogEntry = #syslog_entry{
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
},

% Convert to NDJSON
JsonString = syslog_ndjson:to_ndjson(SyslogEntry),
% Result: "{\"priority\":13,\"facility\":1,\"severity\":5,...}\n"
```

### Validating a Syslog Entry

```erlang
% Basic validation (allows null values for nullable fields)
case syslog_ndjson_validator:validate(SyslogEntry) of
    ok ->
        io:format("Valid syslog entry~n");
    {error, Reasons} ->
        io:format("Invalid syslog entry: ~p~n", [Reasons])
end.

% Strict validation (validates format even for null fields)
case syslog_ndjson_validator:validate_strict(SyslogEntry) of
    ok ->
        io:format("Valid syslog entry~n");
    {error, Reasons} ->
        io:format("Invalid syslog entry: ~p~n", [Reasons])
end.
```

## Syslog Record Format

The `syslog_entry` record follows the RFC 5424 specification and includes:

| Field | Type | Description |
|-------|------|-------------|
| priority | integer | Priority value (facility * 8 + severity) |
| facility | integer | Facility code (0-23) |
| severity | integer | Severity level (0-7) |
| version | integer | Syslog protocol version (always 1 for RFC 5424) |
| timestamp | string | ISO8601/RFC3339 formatted timestamp |
| hostname | string or null | Originator hostname |
| app_name | string or null | Application name (max 48 chars) |
| proc_id | string or null | Process ID (max 128 chars) |
| msg_id | string or null | Message ID (max 32 chars) |
| structured_data | map or null | Structured data elements |
| message | string or null | The log message text |

## OpenAPI Specification

The project includes an OpenAPI specification (syslog_ndjson.yaml) that formally defines the structure and constraints of the syslog entries. This specification is used by the validator module to ensure compliance.

## Testing

Run the included EUnit tests:

```shell
$ make test
```
