package Plugins::AirPlay::ChunkedHTTP;

# $Id$

# Logitech Media Server Copyright 2003-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# This class provides an async HTTP implementation for chunked encoding
# only. 

use strict;
use base 'Slim::Networking::Async';

use HTTP::Response;

use Slim::Networking::Select;
use Slim::Networking::Async::Socket;

use Slim::Utils::Log;

my $log = logger('plugin.airplay');

__PACKAGE__->mk_accessor(
        rw => qw(
          uri request response saveAs fh timeout maxRedirect buffer content_parser
          )
);

use constant BUFSIZE   => 16 * 1024;
use constant MAX_REDIR => 7;

sub new_socket {
        my $self   = shift;
        my $socket = Slim::Networking::Async::Socket::HTTP->new(@_);
        $socket->set( "buf",     "" );
        $socket->set( "bufsize", 0 );
        $$socket->{chunked} = -1;
        return $socket;
}

sub send_request {
        my ( $self, $args ) = @_;

        $self->request( $args->{request} );

        $self->request->protocol('HTTP/1.1');

        $self->write_async(
                {
                        host        => $self->request->uri->host,
                        port        => $self->request->uri->port,
                        content_ref => \&_format_request,
                        Timeout     => $self->timeout,
                        onError     => \&_http_error,
                        onRead      => \&_http_read,
                        passthrough => [$args],
                }
        );

}

sub use_proxy {
        my $self = shift;
        return;
}

sub _format_request {
        my $self = shift;

        my $fullpath = $self->request->uri->path_query;

        $self->content_parser( \&_parse_header );

        $self->socket->http_version('1.1');

        my $request = $self->socket->format_request( $self->request->method, $fullpath, );

        $log->debug("request '$request'");
        return \$request;
}

sub _http_error {
        my ( $self, $error, $args ) = @_;

        # If there is no airplay proxy active this will overflow the log file.
        #	$log->error("Error: [$error]");

        if ( my $cb = $args->{onDisconnect} ) {
                my $passthrough = $args->{passthrough} || [];
                $cb->( $self, @{$passthrough} );
        }
}

sub _get_args {
        my ($self) = @_;

        my $socket_args = ${ $self->socket }->{passthrough};
        my $args        = $$socket_args[1]->{passthrough};
        return $$args[0];
}

sub _disconnect {
        my ($self) = @_;

        my $args = $self->_get_args();

        Slim::Networking::Select::removeError( $self->socket );
        Slim::Networking::Select::removeRead( $self->socket );
        Slim::Networking::Select::removeWrite( $self->socket );

        close( $self->socket );

        if ( my $cb = $args->{onDisconnect} ) {
##	    $log->debug( "_disconnect: calling callback..." );

                my $passthrough = $args->{passthrough} || [];
                $cb->( $self, @{$passthrough} );
        }
}

sub _sysread {

        #    my( $self, $socket, $buf, $size, $offset )= @_;
        my $self = shift;
        return sysread( $_[0], $_[1], $_[2], $_[3] );
}

sub log_state {
        my ( $self, $ref ) = @_;

        my $socket = $self->socket;

##	$log->debug( "$ref:0: buf[$$socket->{bufsize}]='".Data::Dump::dump($$socket->{buf})."'" );
}

sub _read_from_socket {
        my ( $self, $ref ) = @_;

        my $socket = $self->socket;

        my $n = 1;
        $self->log_state("$ref:0");
        $n = $self->_sysread( $self->socket, $$socket->{buf}, 10000, $$socket->{bufsize} );
##	$log->debug( "n=$n" );

        if ( $n == 0 ) {
                $self->_disconnect();
                die "Socket disconnected!";
        }
        if ( $n > 0 ) {
                $$socket->{bufsize} += $n;
        }
        $self->log_state("$ref:2");
        return $$socket->{buf};
}

sub getline {
        my ($self) = @_;

        $self->log_state("getline:i:");

        my $socket = $self->socket;

        if ( $$socket->{buf} =~ /\r\n/ ) {
                my ( $line, $rest ) = split( /\r\n/, $$socket->{buf}, 2 );

                $self->socket->set( "buf",     $rest );
                $self->socket->set( "bufsize", $$socket->{bufsize} - length($line) - 2 );
                $self->log_state("getline:r:");
                return $line;
        }
        return undef;
}

sub getdata {
        my ( $self, $size ) = @_;

        $self->log_state("getdata:i:size=$size");

        my $socket = $self->socket;

        if ( $$socket->{bufsize} >= $size ) {
                my $rv = substr( $$socket->{buf}, 0, $size );
                $$socket->{buf} = substr( $$socket->{buf}, $size );
                $$socket->{bufsize} -= $size;
                $self->log_state("getdata:r:");
                return $rv;
        }
        return undef;
}

sub _http_read_header {
        my ( $self, $args ) = @_;

        my $socket = $self->socket;

        $self->_read_from_socket("_http_read_header");

        while ( defined( my $line = $self->getline() ) ) {
                if ( $line eq "" ) {
##			$log->debug( "starting to read chunks" );

                        $$socket->{chunked} = -1;
                        $$socket->{body}    = 1;
                        if ( my $cb = $args->{onHeaders} ) {
                                my $passthrough = $args->{passthrough} || [];
##				$log->debug( "starting to read chunks calling callback!" );
                                $cb->( $self, @{$passthrough} );
                        }

                        #			$self->response( HTTP::Response->new( $code, $mess, $headers ) );
                        $self->response( HTTP::Response->new( 200, "Yo!" ) );
##			$log->debug( "starting to read chunks done" );

                        $self->_http_parse_content($args);
                        return;
                }
        }
}

sub _http_read_content {
        my ( $self, $args ) = @_;

        $self->_read_from_socket("_http_read_content");
        $self->_http_parse_content($args);
}

# $chunked states:
#  -1 - Read the chunk header.
#  0 - Read the newline at the end of the chunk
#  >0 - The number of bytes to read in the chunk
sub _http_parse_content {
        my ( $self, $args ) = @_;

        my $socket   = $self->socket;
        my $continue = 1;

        while ($continue) {
##		$log->debug( "chunked=$$socket->{chunked}\n" );
                if ( $$socket->{chunked} == 0 ) {
                        my $line = $self->getline();
                        return if !defined $line;
                        if ( $line ne "" ) {
                                $self->_disconnect();
                                die "Bad End-Of-Chunk line, synchronization lost";
                        }
                        $$socket->{chunked} = -1;
                }
                if ( $$socket->{chunked} < 0 ) {
                        my $line = $self->getline();
##			$log->debug( "chunk header line: $line" );
                        return if !defined $line;
                        my ( $chunk_len, $extensions ) = split( ";", $line, 2 );
                        $self->response->header( chunk_extensions => $extensions );
                        unless ( $chunk_len =~ /^([\da-fA-F]+)\s*$/ ) {
                                $log->warning("disconnecting on bad header");
                                $self->_disconnect();
                                die "Bad chunk-size in HTTP response: $line";
                        }
                        $$socket->{chunked} = hex($1);

                        if ( $$socket->{chunked} <= 0 ) {
##				$log->debug( "Last chunk sent." );
                                $continue = 0;
                        }
                }

                # OK, read the chunk if possible
                my $data = $self->getdata( $$socket->{chunked} );
                if ( !defined $data ) {
                        return;
                }
##		$log->debug( "DATA: ".Data::Dump::dump( $data ));
                $self->response->content($data);

                if ( my $cb = $args->{onChunk} ) {

                        # Here we have a complete chunk and the client wants each chunk.
                        my $passthrough = $args->{passthrough} || [];
                        $continue = $cb->( $self, @{$passthrough} );
                }
                $$socket->{chunked} = 0;

                if ( $continue == 0 ) {
                        $log->debug("Closing socket.");
                        $self->socket->close();
                        return;
                }
        }
}

sub _http_read {
        my ( $self, $args ) = @_;

        if ( ${ $self->socket }->{body} ) {
                $self->_http_read_content($args);
        }
        else {
                $self->_http_read_header($args);
        }
}

sub init {
}

1;
