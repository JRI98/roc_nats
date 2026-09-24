app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst",
}

import pf.Stdout
import pf.Tcp
import pf.IOErr exposing [IOErr]

default_ip = "127.0.0.1"

default_port = 4222

timeout_ms = 60_000

max_bytes = 1_048_576

crlf = ['\r', '\n']

Headers : {
	version : Str,
	fields : Dict(Str, Str),
}

parse_headers : List(U8) -> Try(Headers, [ParsingFailure(Str), BadUtf8({ problem : Str.Utf8Problem, index : U64 })])
parse_headers = |bytes| {
	str = Str.from_utf8(bytes)?
	lines = Str.split_on(str, "\r\n")
	match lines {
		[version, ..] if Str.starts_with(version, "NATS/") => {
			non_empty_lines =
				List.drop_first(lines, 1)
					|> List.keep_if(|line| Str.count_utf8_bytes(line) > 0)
			fields = parse_header_fields(non_empty_lines, Dict.empty())?
			Ok({ version, fields })
		}
		other => Err(ParsingFailure("Invalid headers: missing NATS version, got ${Str.inspect(other)}"))
	}
}

parse_header_fields : List(Str), Dict(Str, Str) -> Try(Dict(Str, Str), [ParsingFailure(Str), BadUtf8({ problem : Str.Utf8Problem, index : U64 })])
parse_header_fields = |lines, acc| {
	match lines {
		[] => Ok(acc)
		[first, .. as rest] => {
			match Str.split_first(first, ":") {
				Ok({ before, after }) =>
					parse_header_fields(rest, Dict.insert(acc, Str.trim_start(before), Str.trim_start(after)))
				Err(NotFound) => Err(ParsingFailure("Invalid header format: ${first}"))
			}
		}
	}
}

encode_headers : Headers -> List(U8)
encode_headers = |headers| {
	Dict.to_list(headers.fields)
		|> List.map(|(k, v)| Str.to_utf8("${k}: ${v}"))
		|> List.prepend(Str.to_utf8(headers.version))
		|> join_with_crlf
		|> List.concat(crlf)
}

join_with_crlf : List(List(U8)) -> List(U8)
join_with_crlf = |lists| {
	match lists {
		[] => []
		[first] => first
		[first, .. as rest] => List.concat(first, List.concat(crlf, join_with_crlf(rest)))
	}
}

ServerInfo : {
	server_id : Str,
	server_name : Str,
	version : Str,
	go : Str,
	host : Str,
	port : U64,
	headers : Bool,
	max_payload : U64,
	proto : U64,
	client_id : Try(U64, [Missing]),
	auth_required : Try(Bool, [Missing]),
	tls_required : Try(Bool, [Missing]),
	tls_verify : Try(Bool, [Missing]),
	tls_available : Try(Bool, [Missing]),
	connect_urls : Try(List(Str), [Missing]),
	ws_connect_urls : Try(List(Str), [Missing]),
	ldm : Try(Bool, [Missing]),
	git_commit : Try(Str, [Missing]),
	jetstream : Try(Bool, [Missing]),
	ip : Try(Str, [Missing]),
	client_ip : Try(Str, [Missing]),
	nonce : Try(Str, [Missing]),
	cluster : Try(Str, [Missing]),
	domain : Try(Str, [Missing]),
}

ConnectOptions : {
	verbose : Bool,
	pedantic : Bool,
	tls_required : Bool,
	auth_token : Try(Str, [Missing]),
	user : Try(Str, [Missing]),
	pass : Try(Str, [Missing]),
	name : Try(Str, [Missing]),
	lang : Str,
	version : Str,
	protocol : U64,
	echo : Try(Bool, [Missing]),
	sig : Try(Str, [Missing]),
	jwt : Try(Str, [Missing]),
	no_responders : Try(Bool, [Missing]),
	headers : Try(Bool, [Missing]),
	nkey : Try(Str, [Missing]),
}

ClientMessage : [
	CONNECT(ConnectOptions),
	PUB({ subject : Str, reply_to : Str, headers : Try(Headers, [Missing]), payload : List(U8) }),
	SUB({ subject : Str, queue_group : Str, sid : Str }),
	UNSUB({ sid : Str, max_msgs : U64 }),
	PING,
	PONG,
]

ServerMessage : [
	INFO(ServerInfo),
	MSG({ subject : Str, sid : Str, reply_to : Str, payload_bytes : U64, header_bytes : Try(U64, [Missing]), total_bytes : Try(U64, [Missing]) }),
	PING,
	PONG,
	OK,
	ERR(Str),
]

opt_str : List(List(U8)), Str, Try(Str, [Missing]) -> List(List(U8))
opt_str = |fields, key, val|
	match val {
		Ok(v) => List.append(fields, Str.to_utf8("\"${key}\":\"${v}\""))
		Err(Missing) => fields
	}

opt_bool : List(List(U8)), Str, Try(Bool, [Missing]) -> List(List(U8))
opt_bool = |fields, key, val|
	match val {
		Ok(v) => List.append(fields, Str.to_utf8("\"${key}\":${if v "true" else "false"}"))
		Err(Missing) => fields
	}

encode_connect : ConnectOptions -> List(U8)
encode_connect = |opts| {
	fields =
		[
			Str.to_utf8("\"verbose\":${if opts.verbose "true" else "false"}"),
			Str.to_utf8("\"pedantic\":${if opts.pedantic "true" else "false"}"),
			Str.to_utf8("\"tls_required\":${if opts.tls_required "true" else "false"}"),
			Str.to_utf8("\"lang\":\"${opts.lang}\""),
			Str.to_utf8("\"version\":\"${opts.version}\""),
			Str.to_utf8("\"protocol\":${U64.to_str(opts.protocol)}"),
		]
			|> opt_str("auth_token", opts.auth_token)
			|> opt_str("user", opts.user)
			|> opt_str("pass", opts.pass)
			|> opt_str("name", opts.name)
			|> opt_bool("echo", opts.echo)
			|> opt_str("sig", opts.sig)
			|> opt_str("jwt", opts.jwt)
			|> opt_bool("no_responders", opts.no_responders)
			|> opt_bool("headers", opts.headers)
			|> opt_str("nkey", opts.nkey)

	json = Str.join_with(List.map(fields, Str.from_utf8_lossy), ",")
	Str.to_utf8("CONNECT {${json}}")
}

encode_str : Str -> List(U8)
encode_str = |s| match s {
	"" => []
	non_empty => List.concat([' '], Str.to_utf8(non_empty))
}

encode_num : U64 -> List(U8)
encode_num = |n| match n {
	0 => []
	positive => List.concat([' '], Str.to_utf8(U64.to_str(positive)))
}

encode_payload : List(U8) -> List(U8)
encode_payload = |b| match b {
	[] => []
	data => List.concat(crlf, data)
}

skip_trailing_crlf! : Tcp.Stream => Try({}, [TcpUnexpectedEOF, TcpReadErr(Tcp.StreamErr)])
skip_trailing_crlf! = |stream| {
	match Tcp.Stream.read_exactly!(stream, 2, timeout_ms) {
		Ok(['\r', '\n']) => Ok({})
		Ok(_) => Err(TcpUnexpectedEOF)
		Err(TcpReadErr(TimedOut)) => skip_trailing_crlf!(stream)
		Err(err) => Err(err)
	}
}

encode_message : ClientMessage -> List(U8)
encode_message = |message|
	match message {
		CONNECT(opts) => encode_connect(opts)

		PUB({ subject, reply_to, headers, payload }) =>
			match headers {
				Ok(hdrs) => {
					encoded = encode_headers(hdrs)
					Str.to_utf8("HPUB")
						|> List.concat(encode_str(subject))
						|> List.concat(encode_str(reply_to))
						|> List.concat(encode_num(List.len(encoded)))
						|> List.concat(encode_num(List.len(encoded) + List.len(payload)))
						|> List.concat(encode_payload(encoded))
						|> List.concat(encode_payload(payload))
				}
				Err(Missing) =>
					Str.to_utf8("PUB")
						|> List.concat(encode_str(subject))
						|> List.concat(encode_str(reply_to))
						|> List.concat(encode_num(List.len(payload)))
						|> List.concat(encode_payload(payload))
				}

		SUB({ subject, queue_group, sid }) =>
			Str.to_utf8("SUB")
				|> List.concat(encode_str(subject))
				|> List.concat(encode_str(queue_group))
				|> List.concat(encode_str(sid))

		UNSUB({ sid, max_msgs }) =>
			Str.to_utf8("UNSUB")
				|> List.concat(encode_str(sid))
				|> List.concat(encode_num(max_msgs))

		PING => Str.to_utf8("PING")
		PONG => Str.to_utf8("PONG")
	}

read_line! : Tcp.Stream, List(U8) => Try(List(U8), [TcpUnexpectedEOF, TcpReadErr(Tcp.StreamErr), TcpReadLimitExceeded(U64)])
read_line! = |stream, acc| {
	match Tcp.Stream.read_exactly!(stream, 1, timeout_ms) {
		Ok(['\n']) =>
			if List.ends_with(acc, ['\r']) {
				Ok(List.drop_last(acc, 1))
			} else {
				Ok(acc)
			}
		Ok(byte) => read_line!(stream, List.concat(acc, byte))
		Err(TcpReadErr(TimedOut)) => read_line!(stream, acc)
		Err(err) => Err(err)
	}
}

read_payload! : Tcp.Stream, U64 => Try(List(U8), [TcpUnexpectedEOF, TcpReadErr(Tcp.StreamErr)])
read_payload! = |stream, num_bytes| {
	payload = Tcp.Stream.read_exactly!(stream, num_bytes, timeout_ms)?
	skip_trailing_crlf!(stream)?
	Ok(payload)
}

read_hmsg! : Tcp.Stream, U64, U64 => Try({ hdr : List(U8), body : List(U8) }, [TcpUnexpectedEOF, TcpReadErr(Tcp.StreamErr)])
read_hmsg! = |stream, hdr_bytes, total_bytes| {
	hdr = Tcp.Stream.read_exactly!(stream, hdr_bytes, timeout_ms)?
	body = Tcp.Stream.read_exactly!(stream, total_bytes - hdr_bytes, timeout_ms)?
	skip_trailing_crlf!(stream)?
	Ok({ hdr, body })
}

decode_server : List(U8) -> Try(ServerMessage, [ParsingFailure(Str), BadUtf8({ problem : Str.Utf8Problem, index : U64 }), InvalidJson(Str), MissingRequiredField(Str), BadNumStr])
decode_server = |bytes|
	match bytes {
		['I', 'N', 'F', 'O', ' ', .. as json_bytes] => {
			json_str = Str.from_utf8(json_bytes)?
			info = Json.parse(json_str)?
			Ok(INFO(info))
		}
		['P', 'I', 'N', 'G'] => Ok(PING)
		['P', 'O', 'N', 'G'] => Ok(PONG)
		['+', 'O', 'K'] => Ok(OK)
		['-', 'E', 'R', 'R', ' ', .. as err_bytes] => {
			err_str = Str.from_utf8(err_bytes)?
			Ok(ERR(err_str))
		}
		['M', 'S', 'G', ' ', .. as fields_bytes] => {
			f = parse_msg_fields(fields_bytes)?
			Ok(MSG({ subject: f.subject, sid: f.sid, reply_to: f.reply_to, payload_bytes: f.num_bytes, header_bytes: Err(Missing), total_bytes: Err(Missing) }))
		}
		['H', 'M', 'S', 'G', ' ', .. as fields_bytes] => {
			f = parse_hmsg_fields(fields_bytes)?
			Ok(MSG({ subject: f.subject, sid: f.sid, reply_to: f.reply_to, payload_bytes: f.total_bytes, header_bytes: Ok(f.header_bytes), total_bytes: Ok(f.total_bytes) }))
		}
		unknown => Err(ParsingFailure("Unknown message: ${Str.inspect(unknown)}"))
	}

parse_msg_fields : List(U8) -> Try({ subject : Str, sid : Str, reply_to : Str, num_bytes : U64 }, [ParsingFailure(Str), BadUtf8({ problem : Str.Utf8Problem, index : U64 }), BadNumStr])
parse_msg_fields = |bytes| {
	parts = Str.split_on(Str.from_utf8(bytes)?, " ")
	match parts {
		[subject, sid, num_str] =>
			Ok({ subject, sid, reply_to: "", num_bytes: U64.from_str(num_str)? })
		[subject, sid, reply_to, num_str] =>
			Ok({ subject, sid, reply_to, num_bytes: U64.from_str(num_str)? })
		other => Err(ParsingFailure("Invalid MSG format: ${Str.inspect(other)}"))
	}
}

parse_hmsg_fields : List(U8) -> Try({ subject : Str, sid : Str, reply_to : Str, header_bytes : U64, total_bytes : U64 }, [ParsingFailure(Str), BadUtf8({ problem : Str.Utf8Problem, index : U64 }), BadNumStr])
parse_hmsg_fields = |bytes| {
	parts = Str.split_on(Str.from_utf8(bytes)?, " ")
	match parts {
		[subject, sid, hdr_str, total_str] =>
			Ok({ subject, sid, reply_to: "", header_bytes: U64.from_str(hdr_str)?, total_bytes: U64.from_str(total_str)? })
		[subject, sid, reply_to, hdr_str, total_str] =>
			Ok({ subject, sid, reply_to, header_bytes: U64.from_str(hdr_str)?, total_bytes: U64.from_str(total_str)? })
		other => Err(ParsingFailure("Invalid HMSG format: ${Str.inspect(other)}"))
	}
}

write_msg! : Tcp.Stream, ClientMessage => Try({}, [TcpWriteErr(Tcp.StreamErr), StdoutErr(IOErr), BadUtf8({ problem : Str.Utf8Problem, index : U64 })])
write_msg! = |stream, message| {
	Stdout.write!("WRITE: ")?
	Stdout.line!(Str.inspect(message))?
	bytes = encode_message(message)
	Tcp.Stream.write!(stream, List.concat(bytes, crlf), timeout_ms)
}

handle_message! : Tcp.Stream => Try({}, [NatsErr(Str), ParsingFailure(Str), MissingRequiredField(Str), InvalidJson(Str), BadUtf8({ problem : Str.Utf8Problem, index : U64 }), OutOfBounds, TcpUnexpectedEOF, TcpReadErr(Tcp.StreamErr), TcpReadLimitExceeded(U64), StdoutErr(IOErr), TcpWriteErr(Tcp.StreamErr), BadNumStr])
handle_message! = |stream| {
	bytes = read_line!(stream, [])?
	message = decode_server(bytes)?

	Stdout.write!("READ: ")?
	Stdout.line!(Str.inspect(message))?

	match message {
		PING => write_msg!(stream, PONG)
		OK => Ok({})
		ERR(err) => Err(NatsErr(err))
		MSG({ payload_bytes, header_bytes, total_bytes, .. }) => {
			match header_bytes {
				Ok(hdr_bytes) => {
					read_result = read_hmsg!(
						stream,
						hdr_bytes,
						match total_bytes {
							Ok(tb) => tb
							Err(Missing) => 0
						},
					)
					match read_result {
						Ok(_) => Ok({})
						Err(err) => Err(err)
					}
				}
				Err(Missing) => {
					read_result = read_payload!(stream, payload_bytes)
					match read_result {
						Ok(_) => Ok({})
						Err(err) => Err(err)
					}
				}
			}
		}
		PONG => Ok({})
		other => Err(NatsErr("Unexpected message: ${Str.inspect(other)}"))
	}
}

handshake! : Tcp.Stream => Try({}, [NatsErr(Str), ParsingFailure(Str), MissingRequiredField(Str), InvalidJson(Str), BadUtf8({ problem : Str.Utf8Problem, index : U64 }), OutOfBounds, TcpUnexpectedEOF, TcpReadErr(Tcp.StreamErr), TcpReadLimitExceeded(U64), StdoutErr(IOErr), TcpWriteErr(Tcp.StreamErr), BadNumStr])
handshake! = |stream| {
	bytes = read_line!(stream, [])?
	msg = decode_server(bytes)?
	Stdout.write!("READ: ")?
	Stdout.line!(Str.inspect(msg))?

	connect_opts = { verbose: True, pedantic: False, tls_required: False, lang: "roc", version: "0.1.0", protocol: 1, auth_token: Err(Missing), user: Err(Missing), pass: Err(Missing), name: Err(Missing), echo: Err(Missing), sig: Err(Missing), jwt: Err(Missing), no_responders: Err(Missing), headers: Err(Missing), nkey: Err(Missing) }

	match msg {
		INFO(_) => write_msg!(stream, CONNECT(connect_opts))
		_ => Err(NatsErr("Expected INFO"))
	}?

	bytes2 = read_line!(stream, [])?
	msg2 = decode_server(bytes2)?
	Stdout.write!("READ: ")?
	Stdout.line!(Str.inspect(msg2))?

	match msg2 {
		OK => Ok({})
		_ => Err(NatsErr("Expected OK"))
	}
}

run! : Tcp.Stream => Try({}, [NatsErr(Str), ParsingFailure(Str), MissingRequiredField(Str), InvalidJson(Str), BadUtf8({ problem : Str.Utf8Problem, index : U64 }), OutOfBounds, TcpUnexpectedEOF, TcpReadErr(Tcp.StreamErr), TcpReadLimitExceeded(U64), StdoutErr(IOErr), TcpWriteErr(Tcp.StreamErr), BadNumStr])
run! = |stream| {
	handshake!(stream)?

	sub_opts = { subject: "test.>", queue_group: "", sid: "1" }
	write_msg!(stream, SUB(sub_opts))?

	pub_opts = { subject: "test.hello", reply_to: "", headers: Err(Missing), payload: Str.to_utf8("Hello from Roc!") }
	write_msg!(stream, PUB(pub_opts))?

	loop!(stream)
}

loop! : Tcp.Stream => Try({}, [NatsErr(Str), ParsingFailure(Str), MissingRequiredField(Str), InvalidJson(Str), BadUtf8({ problem : Str.Utf8Problem, index : U64 }), OutOfBounds, TcpUnexpectedEOF, TcpReadErr(Tcp.StreamErr), TcpReadLimitExceeded(U64), StdoutErr(IOErr), TcpWriteErr(Tcp.StreamErr), BadNumStr])
loop! = |stream| {
	handle_message!(stream)?
	loop!(stream)
}

main! : List([Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]) => Try({}, [Exit(I32), StdoutErr(IOErr)])
main! = |_| {
	Stdout.line!("Connecting to NATS at ${default_ip}:${U16.to_str(default_port)}")?

	match Tcp.connect!(default_ip, default_port, timeout_ms) {
		Ok(stream) => {
			Stdout.line!("Successfully connected")?
			match run!(stream) {
				Ok({}) => Ok({})
				Err(err) => {
					Stdout.write!("ERROR: ")?
					Stdout.line!(Str.inspect(err))?
					Err(Exit(1))
				}
			}
		}
		Err(err) => {
			Stdout.write!("CONNECTION ERROR: ")?
			Stdout.line!(Str.inspect(err))?
			Err(Exit(1))
		}
	}
}
