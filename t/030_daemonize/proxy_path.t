use strict;
use warnings;
BEGIN { $ENV{TEST_LIGHTTPD} = 0 }
use t::Utils;
use Test::More;

plan tests => 4*interfaces;

use LWP::UserAgent;
use HTTP::Engine;

daemonize_all sub {
    my ($port, $interface) = @_;

    my $ua = LWP::UserAgent->new(timeout => 10);
    $ua->proxy('http', "http://localhost:$port/");
    my $res = $ua->get("http://example.com/foo?http=1");
    is $res->code, 200, $interface;
    is $res->content, '/|http://example.com/foo?http=1'; # which one is best?

    $res = $ua->get("http://example.com:8080/foo?http=1");
    is $res->code, 200, $interface;
    is $res->content, '/|http://example.com:8080/foo?http=1'; # which one is best?
} => <<'...';
    sub {
        my $port = shift;
        return (
            poe_kernel_run => 1,
            interface => {
                args => {
                    port => $port,
                },
                request_handler => sub {
                    my $req = shift;
                    HTTP::Engine::Response->new(
                        status => 200,
                        body   => $req->uri->path.'|'.$req->proxy_request,
                    );
                },
            },
        );
    }
...

