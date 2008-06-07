package HTTP::Engine::Role::Interface;
use strict;
use Moose::Role;
use HTTP::Engine::ResponseWriter;
use HTTP::Engine::Types::Core qw( Handler );

requires qw(run should_write_response_line);

has request_handler => (
    is       => 'rw',
    isa      => Handler,
    coerce   => 1,
    required => 1,
);

sub request_processor_class {
    return "HTTP::Engine::RequestProcessor";
}

sub request_processor_traits {
    return;
}

has request_processor => (
    is         => 'ro',
    isa        => 'HTTP::Engine::RequestProcessor',
    lazy_build => 1,
    handles    => [qw/handle_request load_plugins/],
);

sub _build_request_processor {
    my $self = shift;

    $self->_class_with_roles("request_processor")->new(
        handler                    => $self->request_handler,
        request_builder            => $self->request_builder,
        response_writer            => $self->response_writer,
    );
}


sub request_builder_class {
    return "HTTP::Engine::RequestBuilder";
}

sub request_builder_traits {
    return;
}

has request_builder => (
    is         => 'ro',
    isa        => 'HTTP::Engine::RequestBuilder',
    lazy_build => 1,
);

sub _build_request_builder {
    my $self = shift;

    $self->_class_with_roles("request_builder")->new;
}


sub response_writer_class {
    return "HTTP::Engine::ResponseWriter";
}

sub response_writer_traits {
    return;
}

has response_writer => (
    is         => 'ro',
    isa        => 'HTTP::Engine::ResponseWriter',
    lazy_build => 1,
);

sub _build_response_writer {
    my $self = shift;

    $self->_class_with_roles("response_writer")->new(
        should_write_response_line => $self->should_write_response_line,
    );
}




my %anon_classes;
sub _class_with_roles {
    my ( $self, $type ) = @_;

    my $m_class  = "${type}_class";
    my $m_traits = "${type}_traits";

    my $class = $self->$m_class;

    if ( my @roles = $self->$m_traits ) {
        my $class_key = join("\0", $class, sort @roles);

        my $metaclass = $anon_classes{$class_key} ||= $self->_create_anon_class($class, @roles);

        return $metaclass->name;
    } else {
        return $class;
    }
}

sub _create_anon_class {
    my ( $self, $class, @roles ) = @_;

    # create an anonymous subclass
    my $anon = $class->meta->create_anon_class(
        superclasses => [ $class ],
    );

    # apply the roles to the class
    Moose::Util::apply_all_roles( $anon->name, @roles );

    return $anon->name;
}

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
