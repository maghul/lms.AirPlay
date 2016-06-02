package Plugins::AirPlay::Chunked;

# $Id$

# Logitech Media Server Copyright 2003-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# This class provides an async HTTP implementation.

use strict;
use base 'Slim::Networking::Async';

use HTTP::Response;

use Slim::Networking::Select;
use Slim::Networking::Async::Socket;

use Slim::Utils::Log;

my $log = logger('plugin.airplay');

__PACKAGE__->mk_accessor(
        rw => qw(
          uri request response saveAs fh timeout maxRedirect buffer
          )
);

use constant BUFSIZE   => 16 * 1024;
use constant MAX_REDIR => 7;

sub new_socket {
        my $self = shift;
        return Slim::Networking::Async::Socket::HTTP->new(@_);
}

sub send_request {
        my ( $self, $args ) = @_;

        $log->error("send_request");

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

        $self->socket->set( "content_parser", \&_parse_header );

        $self->socket->http_version('1.1');

        my $request = $self->socket->format_request( $self->request->method, $fullpath, );

        $log->error("request '$request'");
        return \$request;
}

sub _http_error {
        my ( $self, $error, $args ) = @_;

        $log->error("Error: [$error]");

        if ( my $cb = $args->{onDisconnect} ) {
                my $passthrough = $args->{passthrough} || [];
                $cb->( $self, @{$passthrough} );
        }
}

sub _parse_header {
        my ( $self, $buf, $bufsize, $args ) = @_;

        #	$log->error("_parser_chunk: buf=$buf" );

        #	$log->error("parse header" );
        if ( $buf =~ /\r\n\r\n/ ) {

                #		$log->error("parse header DONE" );
                $self->response( HTTP::Response->new( 200, "Hunky Dory" ) );
                $self->socket->set( "content_parser", \&_parse_chunk );
                if ( my $cb = $args->{onConnect} ) {
                        my $passthrough = $args->{passthrough} || [];
                        $cb->( $self, @{$passthrough} );
                }

                return index( $buf, "\r\n\r\n" ) + 4;
        }
        return 0;

}

sub _parse_chunk {
        my ( $self, $buf, $bufsize, $args ) = @_;

        #	$log->error("_parser_chunk: buf=$buf" );
        my $eol = index( $buf, "\r\n" );
        if ( !$eol ) {
                return 0;
        }
        my $chunk_line = substr( $buf, 0, $eol );

        #	$log->error("Read chunk_line=$chunk_line" );
        my $chunk_len = $chunk_line;
        $chunk_len =~ s/;.*//;    # ignore potential chunk parameters

        #	$log->error("Read chunk_len=$chunk_len" );
        unless ( $chunk_len =~ /^([\da-fA-F]+)\s*$/ ) {
                $self->_http_error( "Bad chunk-size in HTTP response: $buf", $args );
                return 0;
        }
        my $chunk_size = hex($1);

        #	$log->error("Read chunk_size=$chunk_size" );
        my $chunk_start = $eol + 2;
        my $chunk_end   = $chunk_start + $chunk_size;
        if ( $bufsize > $chunk_end ) {

                # We have a complete chunk
                my $chunk = substr( $buf, $chunk_start, $chunk_end - $chunk_start );

                #		$log->error("Read chunk=$chunk" );

                if ( my $cb = $args->{onBody} ) {
                        my $passthrough = $args->{passthrough} || [];
                        $self->response->content($chunk);
                        $cb->( $self, @{$passthrough} );
                }

                return $chunk_end + 2;
        }
        return 0;
}

sub _disconnect {
        my ( $self, $args ) = @_;

        # headers complete, remove ourselves from select loop
        Slim::Networking::Select::removeError( $self->socket );
        Slim::Networking::Select::removeRead( $self->socket );
        Slim::Networking::Select::removeWrite( $self->socket );

        close( $self->socket );

        if ( my $cb = $args->{onDisconnect} ) {
                my $passthrough = $args->{passthrough} || [];
                $cb->( $self, @{$passthrough} );
        }
}

sub _http_read {
        my ( $self, $args ) = @_;

        #	$log->error("Read");

        my $buf     = $self->socket->get("buf");
        my $bufsize = $self->socket->get("bufsize");
        while (1) {
                my $n = sysread( $self->socket, $buf, 10000, $bufsize );
                if ( !defined $n ) {
                        $self->socket->set( "buf",     $buf );
                        $self->socket->set( "bufsize", $bufsize );
                        return;
                }
                $bufsize += $n;

                #		$log->error("Read n=$n" );
                #		$log->error("Read bufsize=$bufsize" );

                if ( $n == 0 ) {
                        $self->_disconnect($args);
                        return;
                }

                my $sp;
                do {
                        my $parser = $self->socket->get("content_parser");

                        #			$log->error("Parsed parser=$parser" );

                        $sp = &$parser( $self, $buf, $bufsize, $args );
                        if ( $sp > 0 ) {
                                $buf = substr( $buf, $sp );
                                $bufsize -= $sp;
                        }

                        #			$log->error("Parsed buf=$buf" );
                } until ( $sp == 0 || $bufsize == 0 );

        }
}

sub init {

        #	$log->error("Init");
}

1;
