local http = require "tritone.http"
local lunit = require "lunit"

local tostring = tostring

module("http_cookie_test", lunit.testcase)

function simple_cookie_test()
    local cookie = http.Cookie:new{name="testName", value="testValue"}
    assert_equal("testName=testValue", tostring(cookie))
end

function maxage_cookie_test()
    local cookie = http.Cookie:new{name="myName", value="myValue", maxage=3600}
    assert_equal("myName=myValue; Max-Age=3600", tostring(cookie))
end

function expires_cookie_test()
    local cookie = http.Cookie:new{name="myName", value="myValue", expires={year=2012, month=3, day=1}}
    assert_equal("myName=myValue; Expires=Thu, 01 Mar 2012 12:00:00 GMT", tostring(cookie))
end

function secure_cookie_test()
    local cookie = http.Cookie:new{name="myName", value="myValue", secure=true}
    assert_equal("myName=myValue; Secure", tostring(cookie))
end

function httponly_cookie_test()
    local cookie = http.Cookie:new{name="myName", value="myValue", httponly=true}
    assert_equal("myName=myValue; HttpOnly", tostring(cookie))
end

function secure_httponly_cookie_test()
    local cookie = http.Cookie:new{name="myName", value="myValue", httponly=true, secure=true}
    assert_equal("myName=myValue; HttpOnly; Secure", tostring(cookie))
end

function domain_cookie_test()
    local cookie = http.Cookie:new{name="myName", value="myValue", domain="www.example.com"}
    assert_equal("myName=myValue; Domain=www.example.com", tostring(cookie))
end

function path_cookie_test()
    local cookie = http.Cookie:new{name="myName", value="myValue", path="/testPath"}
    assert_equal("myName=myValue; Path=/testPath", tostring(cookie))
end
