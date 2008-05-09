package HTTP::Engine::Response;
use Moose;

use HTTP::Headers;
use HTTP::Engine::Types::Core qw( Header );
use File::stat;

has body => (
    is      => 'rw',
    isa     => 'Any',
    default => '',
);

has context => (
    is  => 'rw',
    isa => 'HTTP::Engine::Context',
);

has cookies => (
    is      => 'rw',
    isa     => 'HashRef',
    default => sub { {} },
);

has location => (
    is  => 'rw',
    isa => 'Str',
);

has status => (
    is      => 'rw',
    isa     => 'Int',
    default => 200,
);

has headers => (
    is      => 'rw',
    isa     => 'Header',
    default => sub { HTTP::Headers->new },
    handles => [ qw(content_encoding content_length content_type header) ],
);

*output = \&body;

sub redirect {
    my $self = shift;

    if (@_) {
        $self->location( shift );
        $self->status( shift || 302 );
    }

    $self->location;
}

sub set_http_response {
    my ($self, $res) = @_;
    $self->status( $res->code );
    $self->headers( $res->headers->clone );
    $self->body( $res->content );
    $self;
}

sub finalize {
    my ($self, $c) = @_;
    confess 'argument missing: $c' unless $c;

    # Handle redirects
    if (my $location = $self->location ) {
        $self->header( Location => $c->req->absolute_url($location) );
        $self->body($self->status . ': Redirect') unless $self->body;
    }

    # Content-Length
    $self->content_length(0);
    if ($self->body) {
        # get the length from a filehandle
        if (Scalar::Util::blessed($self->body) && $self->body->can('read') or ref($self->body) eq 'GLOB') {
            if (my $stat = stat $self->body) {
                $self->content_length($stat->size);
            } else {
                warn 'Serving filehandle without a content-length';
            }
        } else {
            $self->content_length(bytes::length($self->body));
        }
    }

    # Errors
    if ($self->status =~ /^(1\d\d|[23]04)$/) {
        $self->headers->remove_header("Content-Length");
        $self->body('');
    }

    $self->content_type('text/html') unless $self->content_type;
    $self->header(Status => $self->status);

    $self->_finalize_cookies();

    $self->body('') if $c->req->method eq 'HEAD';
}

sub _finalize_cookies  {
    my $self = shift;

    for my $name (keys %{ $self->cookies }) {
        my $val = $self->cookies->{$name};
        my $cookie = (
            Scalar::Util::blessed($val)
            ? $val
            : CGI::Simple::Cookie->new(
                -name    => $name,
                -value   => $val->{value},
                -expires => $val->{expires},
                -domain  => $val->{domain},
                -path    => $val->{path},
                -secure  => $val->{secure} || 0
            )
        );

        $self->headers->push_header('Set-Cookie' => $cookie->as_string);
    }
}

__PACKAGE__->meta->make_immutable;

1;
