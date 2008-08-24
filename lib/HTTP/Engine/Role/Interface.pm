package HTTP::Engine::Role::Interface;
use strict;
use Moose::Role;
use HTTP::Engine::ResponseWriter;
use HTTP::Engine::Types::Core qw( Handler );
use HTTP::Engine::RequestProcessor;

requires 'run', '_build_response_writer', '_build_request_builder';

has request_handler => (
    is       => 'rw',
    isa      => Handler,
    coerce   => 1,
    required => 1,
);

has request_processor => (
    is         => 'ro',
    does       => 'HTTP::Engine::Role::RequestProcessor',
    lazy_build => 1,
    handles    => [qw/handle_request/],
);

sub _build_request_processor {
    my $self = shift;

    HTTP::Engine::RequestProcessor->new(
        handler                    => $self->request_handler,
        request_builder            => $self->request_builder,
        response_writer            => $self->response_writer,
    );
}

has request_builder => (
    is         => 'ro',
    does       => 'HTTP::Engine::Role::RequestBuilder',
    lazy_build => 1,
);

has response_writer => (
    is         => 'ro',
    does       => 'HTTP::Engine::Role::ResponseWriter',
    lazy_build => 1,
);

1;

__END__

=head1 NAME

HTTP::Engine::Role::Interface - The Interface Role Definition

=head1 SYNOPSIS

  package HTTP::Engine::Interface::CGI;
  use Moose;
  with 'HTTP::Engine::Role::Interface';

=head1 DESCRIPTION

HTTP::Engine::Role::Interface defines the role of an interface in HTTP::Engine.

Specifically, an Interface in HTTP::Engine needs to do at least two things:

=over 4

=item Create a HTTP::Engine::Request object from the client request

If you are on a CGI environment, you need to receive all the data from 
%ENV and such. If you are running on a mod_perl process, you need to muck
with $r. 

In any case, you need to construct a valid HTTP::Engine::Request object
so the application handler can do the real work.

=item Accept a HTTP::Engine::Response object, send it back to the client

The application handler must return an HTTP::Engine::Response object.

In turn, the interface needs to do whatever necessary to present this
object to the client. In a  CGI environment, you would write to STDOUT.
In mod_perl, you need to call the appropriate $r->headers methods and/or
$r->print

=back

=head1 AUTHORS

Kazuhiro Osawa and HTTP::Engine Authors

=head1 SEE ALSO

L<HTTP::Engine>

=cut
