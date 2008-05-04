use Test::Base;
use HTTP::Engine::Request;

plan tests => 1*blocks;

run {
    my $block = shift;
    my $req = HTTP::Engine::Request->new( base => URI->new($block->base) );
    is $req->absolute_url( $block->location ), $block->expected;
}

__END__

=== basic
--- base: http://localhost/
--- location: /
--- expected: http://localhost/

=== https
--- base: https://localhost/
--- location: /
--- expected: https://localhost/

=== with port
--- base: http://localhost:59559/
--- location: /
--- expected: http://localhost:59559/

=== with path
--- base: http://localhost/
--- location: /add
--- expected: http://localhost/add

