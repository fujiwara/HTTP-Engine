use strict;
use warnings;
use t::Utils;
use Test::More;

plan skip_all => "HTTP::Engine does not a proxy";
plan tests => 2*interfaces;

use LWP::UserAgent;
use HTTP::Engine;

daemonize_all sub {
    my ($port, $interface) = @_;

    my $ua = LWP::UserAgent->new(timeout => 10);
    $ua->proxy('http', "http://localhost:$port/");
    my $res = $ua->get("http://localhost:$port/?http=1");
    is $res->code, 200, $interface;
    is $res->content, '/'; # which one is best?
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
                        body   => $req->uri->path,
                    );
                },
            },
        );
    }
...
