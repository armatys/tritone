local http = require "tritone.http"
local lunit = require "lunit"
local cmp = require "perun.lang.compare"
local deepeq = cmp.deepeq

module("http_test", lunit.testcase)

local dumpHeaders = http.dumpHeaders
local parseQuery = http.parseUrlEncodedQuery
local parseCookie = http.parseCookieHeader

local body = nil
local boundary = nil
local dumped = nil
local parsed = nil

function setup()
  body = nil
  boundary = nil
  dumped = nil
  parsed = nil
end

function dump_headers_test()
  assert(dumpHeaders{["Content-Type"]="text/html"} == "Content-Type: text/html\r\n", "Dumps header table to string")

  dumped = dumpHeaders{["Content-Length"]=38, Vary="Accept-Language"}
  assert(dumped == "Content-Length: 38\r\nVary: Accept-Language\r\n" or dumped == "Vary: Accept-Language\r\nContent-Length: 38\r\n", "Dumps table with two headers")

  dumped = dumpHeaders{["Set-Cookie"]={"one=two", "three=four"}}
  assert(dumped == "Set-Cookie: one=two\r\nSet-Cookie: three=four\r\n" or dumped == "Set-Cookie: three=four\r\nSet-Cookie: one=two\r\n", "Dumps headers table with multiple 'Set-Cookie' values")
end

function parse_query_test()
  assert(deepeq(parseQuery("one="), {one=""}), "Parse query with one empty parameters")

  assert(deepeq(parseQuery("one=2"), {one="2"}), "Parse query with one parameters")

  assert(deepeq(parseQuery("one=two&three=four"), {one="two", three="four"}), "Parse query with two parameters")

  assert(deepeq(parseQuery("one=&three=four"), {one="", three="four"}), "Parse query with two parameters (one empty)")

  assert(deepeq(parseQuery("one=hello%20one%2B1&three=four%26five"), {one="hello one+1", three="four&five"}), "Parse query with escaped characters")
end

function parse_cookie_test()
  assert(deepeq(parseCookie("name=value"), {name="value"}), "Parse cookie header with one cookie-pair ver. 1")

  assert(deepeq(parseCookie("name=value; "), {name="value"}), "Parse cookie header with one cookie-pair ver. 2")

  assert(deepeq(parseCookie("one=two;three=four"), {one="two", three="four"}), "Parse cookie header with two cookie-pairs ver. 1")

  assert(deepeq(parseCookie("one=two; three=four"), {one="two", three="four"}), "Parse cookie header with two cookie-pairs ver. 2")

  assert(deepeq(parseCookie("one=; three=four"), {one="", three="four"}), "Parse cookie header with two cookie-pairs (one empty value)")

  assert(deepeq(parseCookie("=two"), {}), "Parse cookie header with invalid cookie-pair")
end

function parse_boundary_string_test()
  assert(http.getMultipartDataBoundary("content-type: multipart/form-data; boundary=----------------------------b1022a4d8cfd\r\n") == "----------------------------b1022a4d8cfd", "Extract a multipart boundary string")

  assert(http.getMultipartDataBoundary("content-type: multipart/form-data\r\n") == nil, "Extract a multipart boundary string")
end

function parse_multipart_message_test()
  boundary = "----------------------------147b8cc548d3"
  body = '------------------------------147b8cc548d3\r\nContent-Disposition: form-data; name="n1"; filename="music.ogg"\r\nContent-Type: audio/ogg\r\n\r\nHello\r\n------------------------------147b8cc548d3\r\nContent-Disposition: form-data; name="id"\r\n\r\n123456 7890\r\n------------------------------147b8cc548d3--\r\n\r\n'
  parsed = http.parseMultipartData(boundary, body)
  assert(deepeq(parsed, {id="123456 7890", n1={content="Hello", ["content-type"]="audio/ogg", filename="music.ogg"}}), "Parse a multipart message (ogg audio file and string with name)")

  boundary = "----------------------------147b8cc548d3"
  body = '------------------------------147b8cc548d3\r\nContent-Disposition: form-data; filename="music.ogg"\r\nContent-Type: audio/ogg\r\n\r\nHello\r\n------------------------------147b8cc548d3\r\nContent-Disposition: form-data; name="id"\r\n\r\n123456 7890\r\n------------------------------147b8cc548d3--\r\n\r\n'
  parsed = http.parseMultipartData(boundary, body)
  assert(deepeq(parsed, {{content="Hello", ["content-type"]="audio/ogg", filename="music.ogg"}, id="123456 7890"}), "Parse a multipart message (ogg audio file withot a name and a string)")

  boundary = "----------------------------147b8cc548d3"
  body = '------------------------------147b8cc548d3\r\nContent-Disposition: form-data; filename="music.ogg"\r\nContent-Type: audio/ogg\r\n\r\nHello\r\n------------------------------147b8cc548d3\r\nContent-Disposition: form-data\r\n\r\n123456 7890\r\n------------------------------147b8cc548d3--\r\n\r\n'
  parsed = http.parseMultipartData(boundary, body)
  assert(deepeq(parsed, {{content="Hello", ["content-type"]="audio/ogg", filename="music.ogg"}, {content="123456 7890", ["content-type"]="text/plain"}}), "Parse a multipart message (ogg audio file and string, both without names)")
end
