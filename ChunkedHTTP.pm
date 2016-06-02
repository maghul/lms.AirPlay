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
        $$socket->{chunked}       = -1;
        $$socket->{stateFunction} = \&_readResponse;
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
                my $passthrough = $args->{passthrough} || [];
                $cb->( $self, @{$passthrough} );
        }
}

sub _sysread {

        #    my( $self, $socket, $buf, $size, $offset )= @_;
        my $self = shift;
        return sysread( $_[0], $_[1], $_[2], $_[3] );
}

# Get a line terminated by <CR><NL> and update the buffer
sub _getline {
        my ($self) = @_;

        my $buffer = $self->buffer;
        if ( $buffer =~ /\r\n/ ) {
                my ( $line, $rest ) = split( /\r\n/, $buffer, 2 );

                $self->buffer($rest);
                return $line;
        }
        return undef;
}

# Read State: Response: Initial state, wait for the HTTP/1.1.... line
sub _readResponse {
        my ( $self, $args ) = @_;

        if ( defined( my $line = $self->_getline() ) ) {
                my $socket = $self->socket;

                my ( $protocol, $code, $message ) = split( / /, $line );
                if ( $protocol =~ /^HTTP\/[0-9]\.[0]/ ) {
                }
                my $resp = HTTP::Response->new( $code, $message );
                $self->response($resp);
                if ( $code == 200 ) {
                        $$socket->{stateFunction} = \&_readHeader;
                        return 1;
                }
        }
        return 0;
}

# Read State: Read Header lines until <CR><NL><CR><NL>. Will not handle them except Transfer-Encoding.
# Will set the chunked flag if the Transfer-Encoding is "chunked".
sub _readHeader {
        my ( $self, $args ) = @_;

        if ( defined( my $line = $self->_getline() ) ) {
                my $socket = $self->socket;

                if ( $line eq "" ) {
                        if ( my $cb = $args->{onHeaders} ) {
                                my $passthrough = $args->{passthrough} || [];
                                $cb->( $self, @{$passthrough} );
                        }

                        if ( $$socket->{chunked} == 1 ) {
                                $$socket->{stateFunction} = \&_readChunkSize;
                        }
                        else {
                                $$socket->{stateFunction} = \&_readContent;
                        }
                        return 1;
                }
                else {
                        my ( $key, $value ) = split( /: */, $line );
                        if ( ( $key eq "Transfer-Encoding" ) && ( $value eq "chunked" ) ) {
                                $$socket->{chunked} = 1;
                        }
                        return 1;
                }
        }
        return 0;
}

# Read State: Anything but chunked. This will close the socket since it only
# handles chunked data.
sub _readContent {
        my $self   = shift;
        my $socket = $self->socket;
        my $buf    = $self->buffer;
        $self->error("only supports chunked encoding.");
        return 0;
}

# Read State: Read a line containing the size of the next chunk.
sub _readChunkSize {
        my ( $self, $args ) = @_;
        my $socket = $self->socket;

        if ( defined( my $line = $self->_getline() ) ) {
                $$socket->{chunkSize}     = hex($line);
                $$socket->{stateFunction} = \&_readChunkContent;
                return 1;
        }
        return 0;
}

# Read State: Read the next chunk. check that it terminates with <CR><NL>
sub _readChunkContent {
        my ( $self, $args ) = @_;
        my $socket = $self->socket;

        my $buffer = $self->buffer;
        my $size   = $$socket->{chunkSize};
        if ( length($buffer) >= $size ) {
                if ( my $cb = $args->{onChunk} ) {
                        my $content = substr( $buffer, 0, $size );
                        $self->response->content($content);

                        # Here we have a complete chunk and the client wants each chunk.
                        my $passthrough = $args->{passthrough} || [];
                        my $continue = $cb->( $self, @{$passthrough} );
                        if ( $continue == 0 ) {
                                $self->socket->close();
                        }
                }
                my $sep = substr( $buffer, $size, 2 );
                if ( $sep ne "\r\n" ) {
                        $self->_error( $args, "Chunk error" );
                }
                $buffer = substr( $buffer, $size + 2 );

                $self->buffer($buffer);
                $$socket->{stateFunction} = \&_readChunkSize;
                return 1;
        }
        return 0;
}

# Send an error to the client, if possible, and close the socket.
sub _error {
        my $self = shift;
        my $args = shift;
        my $msg  = shift;

        if ( my $cb = $args->{onError} ) {
                $cb->( $self, $msg );
        }
        else {
                print "Unhandled error: $msg\n";
        }
        $self->socket->close();
}

# Called by select when there is new data. Will read and append to the
# buffer and then call the current read-state closure until nothing more
# can be read from the buffer.
sub _http_read {
        my ( $self, $args ) = @_;

        my $socket = $self->socket;

        my $n      = 1;
        my $buffer = $self->buffer;
        my $offset = length($buffer);
        $n = $self->_sysread( $self->socket, $buffer, 10000, $offset );

	if ( ! defined $n ) {
		$log->debug("_sysread returned undefined, error is:".$!);
                $self->_disconnect();
                die "Socket disconnected!";
	} elsif ( $n == 0 ) {
		$log->debug("_sysread returned 0, is the socket really closed?");
                $self->_disconnect();
                die "Socket disconnected!";
        }
        $self->buffer($buffer);

        my $socket = $self->socket;
        while (1) {
                my $stateFunction = $$socket->{stateFunction};
                if ( &$stateFunction( $self, $args ) == 0 ) {
                        return;
                }
        }
}

sub init {
}

1;
