package HTTP::Engine;
use strict;
use warnings;
BEGIN { eval "package HTTPEx; sub dummy {} 1;" }
use base 'HTTPEx';
use Class::Component;
our $VERSION = '0.0.2';

use Carp;
use Scalar::Util;
use URI;

use HTTP::Engine::Context;
use HTTP::Engine::Request;
use HTTP::Engine::Response;

__PACKAGE__->load_components(qw/Plaggerize Autocall::InjectMethod/);

sub new {
    my ($class, %opts) = @_;

    my $self = $class->NEXT( 'new' => { config => delete $opts{config} } );
    $self->set_handle_request(delete $opts{handle_request}) if $opts{handle_request};

    $self->conf->{global}->{log}->{fh} ||= \*STDERR;

    return $self;
}

sub run { die "404 Engine not found!" }

sub set_handle_request {
    my($self, $callback) = @_;
    croak 'please CODE refarence' unless $callback && ref($callback) eq 'CODE';
    $self->{handle_request} = $callback;
}

sub prepare_request {}
sub prepare_connection {}
sub prepare_query_parameters {}
sub prepare_headers {}
sub prepare_cookie {}
sub prepare_path {}
sub prepare_body {}
sub prepare_body_parameters {}
sub prepare_parameters {}
sub prepare_uploads {}
sub errors { shift->{errors} }
sub push_errors { push @{ shift->{errors} }, @_ }
sub clear_errors { shift->{errors} = [] }

sub handle_request {
    my $self = shift;

    $self->clear_errors();

    $self->run_hook( 'initialize' );

    my $context = HTTP::Engine::Context->new({
        engine => $self,
        req    => HTTP::Engine::Request->new,
        res    => HTTP::Engine::Response->new,
        conf   => $self->conf,
    });
    if (my %env = @_) {
        $context->env(\%env);
    } else {
        $context->env(\%ENV);
    }
    for my $method (qw/ request connection query_parameters headers cookie path body body_parameters parameters uploads /) {
        my $method = "prepare_$method";
        $self->$method($context);
    }

    my $ret = eval {
        $self->{handle_request}->($context);
    };
    if (my $e = $@) {
        $self->push_errors($e);
        $self->run_hook('handle_error', $context);
    }
    $self->finalize($context);

    $ret;
}

sub finalize {
    my($self, $c) = @_;

    $self->finalize_headers($c); # finalize_headers
    $c->res->body('') if $c->req->method eq 'HEAD';
    $self->finalize_body($c); # finalize_body
}

sub finalize_headers {
    my($self, $c) = @_;
    return if $c->res->{_finalized_headers};

    # Handle redirects
    if (my $location = $c->res->redirect ) {
        $self->log( debug => qq/Redirecting to "$location"/ );
        $c->res->header( Location => $self->absolute_url($c, $location) );
        $c->res->body($c->res->status . ': Redirect') unless $c->res->body;
    }

    # Content-Length
    $c->res->content_length(0);
    if ($c->res->body && !$c->res->content_length) {
        # get the length from a filehandle
	if (Scalar::Util::blessed($c->res->body) && $c->res->body->can('read')) {
	    if (my $stat = stat $c->res->body) {
                $c->res->content_length($stat->size);
            } else {
                $self->log( warn => 'Serving filehandle without a content-length' );
            }
	} else {
	    $c->res->content_length(bytes::length($c->res->body));
        }
    }

    # Errors
    if ($c->res->status =~ /^(1\d\d|[23]04)$/) {
        $c->res->headers->remove_header("Content-Length");
        $c->res->body('');
    }

    $self->finalize_cookies($c);
    $self->finalize_output_headers($c);

    # Done
    $c->res->{_finalized_headers} = 1;
}

sub finalize_cookies {}
sub finalize_output_headers {}
sub finalize_body {
    my $self = shift;
    $self->finalize_output_body(@_);
}
sub finalize_output_body {}


sub absolute_url {
    my($self, $c, $location) = @_;

    unless ($location =~ m!^https?://!) {
        my $base = $c->req->base;
        my $url = sprintf '%s://%s', $base->scheme, $base->host;
        unless (($base->scheme eq 'http' && $base->port eq '80') ||
               ($base->scheme eq 'https' && $base->port eq '443')) {
            $url .= ':' . $base->port;
        }
        $url .= $base->path;
        $location = URI->new_abs($location, $url);
    }
    $location;
}

1;
__END__

=encoding utf8

=head1 NAME

HTTP::Engine - Web Server Gateway Interface and HTTP Server Engine Drivers (Yet Another Catalyst::Engine)

=head1 SYNOPSIS

  use HTTP::Engine;
  HTTP::Engine->new(
    config         => 'config.yaml',
    handle_request => sub {
      my $c = shift;
      $c->res->body( Dumper($e->req) );
    }
  )->run;

=head1 CONCEPT RELEASE

Version 0.0.x is Concept release, An internal interface is chiefly fluid. 
It is chiefly based on the code of Catalyst::Engine.

=head1 DESCRIPTION

HTTP::Engine is a bare-bones, extensible HTTP engine. Not, it's not a 
socket binding server. Its purpose is to be an adaptor to various HTTP
based logic layers and the actual implementation of an HTTP server,
for example, mod_perl and FastCGI

=head1 PLUGINS

For all non-core plugins (consult at #codrepos first), use the HTTPEx::
namespace. For example, if you have a plugin module named "HTTPEx::Plugin::Foo",
you should load it as

  use HTTP::Engine;
  HTTP::Engnie->load_plugins(qw( +HTTPEx::Plugin::Foo ));

=head1 AUTHOR

Kazuhiro Osawa E<lt>ko@yappo.ne.jpE<gt>

=head1 COMMITTERS

lestrrat

tokuhirom

=head1 SEE ALSO

=head1 REPOSITORY

  svn co http://svn.coderepos.org/share/lang/perl/HTTP-Engine/trunk HTTP-Engine

HTTP::Engine is Subversion repository is hosted at L<http://coderepos.org/share/>.
patches and collaborators are welcome.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
