package HTTP::Engine::ResponseFinalizer;
use strict;
use warnings;
use CGI::Simple::Cookie ();
use Scalar::Util        ();
use Carp                ();

sub finalize {
    my ($class, $req, $res) = @_;
    Carp::confess 'argument missing: $res' unless $res;

    # protocol
    $res->protocol( $req->protocol ) unless $res->protocol;

    # Content-Length
    if ($res->body) {
        # get the length from a filehandle
        if ((Scalar::Util::blessed($res->body) && $res->body->can('read')) || (ref($res->body) eq 'GLOB')) {
            HTTP::Engine::Util::require_once('File/stat.pm');
            if (my $stat = eval { File::stat::stat($res->body) }) {
                $res->content_length($stat->size);
            } else {
                die "Serving filehandle without a content-length($@)";
            }
        } else {
            $res->content_length(bytes::length($res->body));
        }
    } else {
        $res->content_length(0);
    }

    # Errors
    if ($res->status =~ /^(1\d\d|[23]04)$/) {
        $res->headers->remove_header("Content-Length");
        $res->body('');
    }

    $res->content_type('text/html') unless $res->content_type;
    $res->header(Status => $res->status);

    $class->_finalize_cookies($res);

    # HTTP/1.1's default Connection: close
    if ($res->protocol && $res->protocol =~ m!1\.1! && !!!$res->header('Connection')) {
        $res->header( Connection => 'close' );
    }

    $res->body('') if $req->method eq 'HEAD';
}

sub _finalize_cookies  {
    my ($class, $res) = @_;

    for my $name (keys %{ $res->cookies }) {
        my $val = $res->cookies->{$name};
        my $cookie = (
            Scalar::Util::blessed($val)
            ? $val
            : CGI::Simple::Cookie->new(
                -name    => $name,
                -value   => $val->{value},
                -expires => $val->{expires},
                -domain  => $val->{domain},
                -path    => $val->{path},
                -secure  => ($val->{secure} || 0)
            )
        );

        $res->headers->push_header('Set-Cookie' => $cookie->as_string);
    }
}

1;
