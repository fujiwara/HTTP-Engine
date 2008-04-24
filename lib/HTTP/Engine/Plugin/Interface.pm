package HTTP::Engine::Plugin::Interface;
use strict;
use warnings;
use base qw( HTTP::Engine::Plugin Class::Accessor::Fast );
__PACKAGE__->mk_accessors(qw/ read_position read_length /);

our $CHUNKSIZE = 4096;

use CGI::Simple::Cookie;
use HTTP::Body;
use HTTP::Headers;
use Scalar::Util;
use URI;
use URI::QueryParam;


sub initialize :Hook {
    my($self, $c) = @_;
    delete $self->{_prepared_read};
    delete $self->{_prepared_write};
}
				       
sub prepare_connection :InterfaceMethod {
    my($self, $c) = @_;

    $c->req->address($c->env->{REMOTE_ADDR});

    PROXY_CHECK:
    {   
        unless ( $c->conf->{using_frontend_proxy} ) {
            last PROXY_CHECK if $c->env->{REMOTE_ADDR} ne '127.0.0.1';
            last PROXY_CHECK if $c->conf->{ignore_frontend_proxy};
        }
        # in apache httpd.conf (RequestHeader set X-Forwarded-HTTPS %{HTTPS}s)
        $c->env->{HTTPS} = $c->env->{HTTP_X_FORWARDED_HTTPS} if $c->env->{HTTP_X_FORWARDED_HTTPS};
        $c->env->{HTTPS} = 'ON' if $c->env->{HTTP_X_FORWARDED_PROTO}; # Pound
        last PROXY_CHECK unless $c->env->{HTTP_X_FORWARDED_FOR};

        # If we are running as a backend server, the user will always appear
        # as 127.0.0.1. Select the most recent upstream IP (last in the list)
        my($ip) = $c->env->{HTTP_X_FORWARDED_FOR} =~ /([^,\s]+)$/;
        $c->req->address($ip);
    }

    $c->req->hostname($c->env->{REMOTE_HOST});
    $c->req->protocol($c->env->{SERVER_PROTOCOL});
    $c->req->user($c->env->{REMOTE_USER});
    $c->req->method($c->env->{REQUEST_METHOD});

    $c->req->secure(1) if $c->env->{HTTPS} && uc $c->env->{HTTPS} eq 'ON';
    $c->req->secure(1) if $c->env->{SERVER_PORT} == 443;
}

sub prepare_query_parameters :InterfaceMethod {
    my($self, $c) = @_;
    my $query_string = $c->env->{QUERY_STRING};

    # replace semi-colons
    $query_string =~ s/;/&/g;

    my $uri = URI->new('', 'http');
    $uri->query($query_string);
    for my $key ( $uri->query_param ) {
        my @vals = $uri->query_param($key);
        $c->req->query_parameters->{$key} = @vals > 1 ? [@vals] : $vals[0];
    }
}

sub prepare_headers :InterfaceMethod {
    my($self, $c) = @_;

    # Read headers from env
    for my $header (keys %{ $c->env }) {
        next unless $header =~ /^(?:HTTP|CONTENT|COOKIE)/i;
        (my $field = $header) =~ s/^HTTPS?_//;
        $c->req->headers->header($field => $c->env->{$header});
    }
}

sub prepare_cookie :InterfaceMethod {
    my($self, $c) = @_;

    if (my $header = $c->req->header('Cookie')) {
        $c->req->cookies( { CGI::Simple::Cookie->parse($header) } );
    }
}

sub prepare_path :InterfaceMethod {
    my($self, $c) = @_;

    my $scheme = $c->req->secure ? 'https' : 'http';
    my $host   = $c->env->{HTTP_HOST}   || $c->env->{SERVER_NAME};
    my $port   = $c->env->{SERVER_PORT} || 80;

    my $base_path;
    if (exists $c->env->{REDIRECT_URL}) {
        $base_path = $c->env->{REDIRECT_URL};
        $base_path =~ s/$c->env->{PATH_INFO}$//;
    } else {
        $base_path = $c->env->{SCRIPT_NAME} || '/';
    }

    # If we are running as a backend proxy, get the true hostname
    PROXY_CHECK:
    {
        unless ($c->conf->{using_frontend_proxy}) {
            last PROXY_CHECK if $host !~ /localhost|127.0.0.1/;
            last PROXY_CHECK if $c->conf->{ignore_frontend_proxy};
        }
        last PROXY_CHECK unless $c->env->{HTTP_X_FORWARDED_HOST};

        $host = $c->env->{HTTP_X_FORWARDED_HOST};

        # backend could be on any port, so
        # assume frontend is on the default port
        $port = $c->req->secure ? 443 : 80;

        # in apache httpd.conf (RequestHeader set X-Forwarded-Port 8443)
        $port = $c->env->{HTTP_X_FORWARDED_PORT} if $c->env->{HTTP_X_FORWARDED_PORT};
    }

    my $path = $base_path . ($c->env->{PATH_INFO} || '');
    $path =~ s{^/+}{};

    my $uri = URI->new;
    $uri->scheme($scheme);
    $uri->host($host);
    $uri->port($port);
    $uri->path($path);
    $uri->query($c->env->{QUERY_STRING}) if $c->env->{QUERY_STRING};

    # sanitize the URI
    $uri = $uri->canonical;
    $c->req->uri($uri);

    # set the base URI
    # base must end in a slash
    $base_path .= '/' unless $base_path =~ /\/$/;
    my $base = $uri->clone;
    $base->path_query($base_path);
    $c->req->base($base);
}

sub prepare_body :InterfaceMethod {
    my($self, $c) = @_;

    # TODO: catalyst のように prepare フェーズで処理せず、遅延評価できるようにする 
    $self->read_length($c->req->header('Content-Length') || 0);
    my $type = $c->req->header('Content-Type');

    unless ($c->req->{_body}) {
        $c->req->{_body} = HTTP::Body->new($type, $self->read_length);
        $c->req->{_body}->{tmpdir} = $c->conf->{uploadtmp}
          if exists $c->conf->{uploadtmp};
    }

    if ($self->read_length > 0) {
        while (my $buffer = $self->read) {
            $self->prepare_body_chunk($c, $buffer);
        }

        # paranoia against wrong Content-Length header
        my $remaining = $self->read_length - $self->read_position;
        if ($remaining > 0) {
            $self->finalize_read;
            die "Wrong Content-Length value: " . $self->read_length;
        }
    }
}

sub prepare_body_chunk {
    my($self, $c, $chunk) = @_;
    $c->req->raw_body($c->req->raw_body.$chunk);
    $c->req->{_body}->add($chunk);
}

sub prepare_body_parameters :InterfaceMethod {
    my($self, $c) = @_;
    $c->req->body_parameters($c->req->{_body}->param);
}

sub prepare_parameters :InterfaceMethod {
    my($self, $c) = @_;

    # We copy, no references
    for my $name (keys %{ $c->req->query_parameters }) {
        my $param = $c->req->query_parameters->{$name};
        $param = ref $param eq 'ARRAY' ? [ @{$param} ] : $param;
        $c->req->parameters->{$name} = $param;
    }

    # Merge query and body parameters
    for my $name (keys %{ $c->req->body_parameters }) {
        my $param = $c->req->body_parameters->{$name};
        $param = ref $param eq 'ARRAY' ? [ @{$param} ] : $param;
        if ( my $old_param = $c->req->parameters->{$name} ) {
            if ( ref $old_param eq 'ARRAY' ) {
                push @{ $c->req->parameters->{$name} },
                  ref $param eq 'ARRAY' ? @$param : $param;
            } else {
                $c->req->parameters->{$name} = [ $old_param, $param ];
            }
        } else {
            $c->req->parameters->{$name} = $param;
        }
    }
}

sub prepare_uploads :InterfaceMethod {
    my($self, $c) = @_;

    my $uploads = $c->req->{_body}->upload;
    for my $name (keys %{ $uploads }) {
        my $files = $uploads->{$name};
        $files = ref $files eq 'ARRAY' ? $files : [$files];

        my @uploads;
        for my $upload (@{ $files }) {
            my $u = HTTP::Server::Wrapper::Request::Upload->new;
            $u->headers(HTTP::Headers->new(%{ $upload->{headers} }));
            $u->type($u->headers->content_type);
            $u->tempname($upload->{tempname});
            $u->size($upload->{size});
            $u->filename($upload->{filename});
            push @uploads, $u;
        }
        $c->req->uploads->{$name} = @uploads > 1 ? \@uploads : $uploads[0];

        # support access to the filename as a normal param
        my @filenames = map { $_->{filename} } @uploads;
        $c->req->parameters->{$name} =  @filenames > 1 ? \@filenames : $filenames[0];
    }
}


# output
sub finalize_cookies :InterfaceMethod {
    my($self, $c) = @_;

    for my $name (keys %{ $c->res->cookies }) {
        my $val = $c->res->cookies->{$name};
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

        $c->res->headers->push_header('Set-Cookie' => $cookie->as_string);
    }
}

sub finalize_output_headers :InterfaceMethod {
    my($self, $c) = @_;

    $c->res->header(Status => $c->res->status);
    $self->write($c->res->headers->as_string("\015\012"));
    $self->write("\015\012");
}

sub finalize_output_body :InterfaceMethod {
    my($self, $c) = @_;
    my $body = $c->res->body;

    no warnings 'uninitialized';
    if (Scalar::Util::blessed($body) && $body->can('read') or ref($body) eq 'GLOB') {
        while (!eof $body) {
            read $body, my ($buffer), $CHUNKSIZE;
            last unless $self->write($buffer);
        }
        close $body;
    } else {
        $self->write($body);
    }
}



# private methods

sub read_chunk { shift; *STDIN->sysread(@_) }
#Apache sub read_chunk { shift->apache->read(@_) }

sub prepare_read {
    my $self = shift;
    $self->read_position(0);
}

sub read {
    my ($self, $maxlength) = @_;

    unless ($self->{_prepared_read}) {
        $self->prepare_read;
        $self->{_prepared_read} = 1;
    }

    my $remaining = $self->read_length - $self->read_position;
    $maxlength ||= $self->config->{chunksize} || $CHUNKSIZE;

    # Are we done reading?
    if ($remaining <= 0) {
        $self->finalize_read;
        return;
    }

    my $readlen = ($remaining > $maxlength) ? $maxlength : $remaining;
    my $rc = $self->read_chunk(my $buffer, $readlen);
    if (defined $rc) {
        $self->read_position($self->read_position + $rc);
        return $buffer;
    } else {
        die "Unknown error reading input: $!";
    }
}

sub finalize_read { undef shift->{_prepared_read} }

sub prepare_write {
    my $self = shift;

    # Set the output handle to autoflush
    *STDOUT->autoflush(1);
}

sub write {
    my($self, $buffer) = @_;

    unless ( $self->{_prepared_write} ) {
        $self->prepare_write;
        $self->{_prepared_write} = 1;
    }

    print STDOUT $buffer unless $self->{_sigpipe};
}

1;

__END__

sub write {
    my($self, $buffer) = @_;

    unless ( $self->{_prepared_write} ) {
        $self->prepare_write;
        $self->{_prepared_write} = 1;
    }

    # FastCGI does not stream data properly if using 'print $handle',                                                          
    # but a syswrite appears to work properly.                                                                                 
    *STDOUT->syswrite($buffer);
}

sub write {
    my($self, $buffer) = @_;

    unless ($self->apache->connection->aborted) {
        return $self->apache->print($buffer);
    }
    return;
}


sub finalize_output_headers :InterfaceMethod {
    my $self = shift;

    for my $name ( $self->c->res->headers->header_field_names ) {
        next if $name =~ /^Content-(Length|Type)$/i;
        my @values = $self->c->res->header($name);
        # allow X headers to persist on error                                                                                 
        if ($name =~ /^X-/i) {
            $self->apache->err_headers_out->add($name => $_) for @values;
        } else {
            $self->apache->headers_out->add($name => $_) for @values;
        }
    }

    # persist cookies on error responses                                                                                      
    if ($self->c->res->header('Set-Cookie') && $self->c->res->status >= 400) {
        for my $cookie ($self->c->res->header('Set-Cookie')) {
            $self->apache->err_headers_out->add('Set-Cookie' => $cookie);
        }
    }

    # The trick with Apache is to set the status code in $apache->status but                                                  
    # always return the OK constant back to Apache from the handler.                                                          
    $self->apache->status($self->c->res->status);
    $self->c->res->status($self->return || $self->ok_constant);

    my $type = $self->c->res->header('Content-Type') || 'text/html';
    $self->apache->content_type($type);

    if (my $length = $self->c->res->content_length) {
        $self->apache->set_content_length($length);
    }

    return 0;
}


sub finalize_output_body :InterfaceMethod {
    my $self = shift;

    $self->SUPER::dispatcher_output_body;

    # Data sent using $self->apache->print is buffered, so we need                                                            
    # to flush it after we are done writing.                                                                                  
    $self->apache->rflush;
}
