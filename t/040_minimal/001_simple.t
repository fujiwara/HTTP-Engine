use strict;
use warnings;
BEGIN {
    *CORE::GLOBAL::time = sub { 1234567890 };
}
use Test::Base;
use HTTP::Engine::MinimalCGI;
use IO::Scalar;
local *HTTP::Headers::Fast::as_string_without_sort = *HTTP::Headers::Fast::as_string;

plan tests => 11;

sub crlf {
    local $_ = shift;
    s/\n/\r\n/gsm;
    $_;
}

sub run_engine {
    my $src = shift;

    local %ENV = (
        REQUEST_METHOD => 'GET',
    );

    my $code = eval "sub { $src }";
    die $@ if $@;

    open(my $fh, '>', \my $got) or die $!;
    select($fh);
    HTTP::Engine->new(
        interface => {
            module => 'MinimalCGI',
            request_handler => $code,
        }
    )->run;
    $got;
}

sub processdate {
    local $_ = shift;
    s/%%\%COOKIE::(\+1d)%%%/CGI::Simple::Util::expires($1, 'cookie')/ge;
    $_;
}

filters {
    handler  => [qw/run_engine/],
    response => [qw/processdate chop crlf/],
};

run_is handler => 'response';

__END__

===
--- handler
my $req = shift;
main::isa_ok $req, 'HTTP::Engine::Request';
HTTP::Engine::Response->new(
    status => 200,
    body => 'hello',
);
--- response
Content-Length: 5
Content-Type: text/html
Status: 200

hello

===
--- handler
my $req = shift;
main::isa_ok $req, 'HTTP::Engine::Request';
my $res = HTTP::Engine::Response->new(
    status => 200,
    body => 'hello',
);
$res->cookies->{'foo'} = {
    value => 3,
    expires => '+1d',
};
$res;
--- response
Content-Length: 5
Content-Type: text/html
Set-Cookie: foo=3; path=/; expires=%%%COOKIE::+1d%%%
Status: 200

hello

===
--- handler
$ENV{QUERY_STRING} = 'oo=ps';

my $req = shift;
HTTP::Engine::Response->new(
    status => 200,
    body => $req->param('oo')||'MISSING oo',
);
--- response
Content-Length: 2
Content-Type: text/html
Status: 200

ps

===
--- handler
$ENV{HTTP_X_FOOBAR} = '2000';
my $req = shift;
my $body  = $req->header('X-Foobar') || 'MISSING HEADER';
   $body .= $req->header('x_fOOBAR') || 'MISSING HEADER';
HTTP::Engine::Response->new(
    status => 200,
    body   => $body
);
--- response
Content-Length: 8
Content-Type: text/html
Status: 200

20002000

=== $res->header
--- handler
my $req = shift;
my $res = HTTP::Engine::Response->new(
    status => 200,
    body   => 'ok'
);
$res->header('X-Foo' => 'bar');
$res;
--- response
Content-Length: 2
Content-Type: text/html
Status: 200
X-Foo: bar

ok

=== $req->parameters
--- handler
my $req = shift;
my $res = HTTP::Engine::Response->new(
    status => 200,
    body   => 'ok'
);
$res->header('X-Foo' => 'bar');
$res;
--- response
Content-Length: 2
Content-Type: text/html
Status: 200
X-Foo: bar

ok

=== $req->method
--- handler
$ENV{REQUEST_METHOD} = "POST";
my $req = shift;
my $res = HTTP::Engine::Response->new(
    status => 200,
    body   => $req->method,
);
$res;
--- response
Content-Length: 4
Content-Type: text/html
Status: 200

POST

=== POST from stdin
--- handler
$ENV{REQUEST_METHOD} = "POST";
$ENV{CONTENT_LENGTH} = 15;
$ENV{CONTENT_TYPE}   = "application/x-www-form-urlencoded";
my $in = IO::Scalar->new(\"aaa=bbb&ccc=ddd") or die $!;
local *STDIN = $in;

my $req = shift;
my $res = HTTP::Engine::Response->new(
    status => 200,
    body   => $req->param('aaa') . $req->param('ccc'),
);
$res;
--- response
Content-Length: 6
Content-Type: text/html
Status: 200

bbbddd

=== $req->upload
--- handler
$ENV{REQUEST_METHOD} = "POST";
$ENV{CONTENT_TYPE}   = "multipart/form-data; boundary=----BOUNDARY";

my $stdin =<<'_END_';
------BOUNDARY
Content-Disposition: form-data; name="test_upload_file"; filename="yappo.txt"
Content-Type: text/plain

SHOGUN
------BOUNDARY--

_END_
$stdin =~ s/\n/\r\n/g;
my $in = IO::Scalar->new(\$stdin) or die $!;
local *STDIN = $in;
$ENV{CONTENT_LENGTH} = length $stdin;

my $req = shift;
my $upload = $req->upload('test_upload_file');
my $res = HTTP::Engine::Response->new(
    status => 200,
    body   => sprintf("filename: %s, size: %s, content: %s",
                  $upload->filename,
                  $upload->size,
                  $upload->slurp,
              ),
);
$res;
--- response
Content-Length: 45
Content-Type: text/html
Status: 200

filename: yappo.txt, size: 6, content: SHOGUN


