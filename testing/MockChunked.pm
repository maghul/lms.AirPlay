#!/usr/bin/perl -w
package MockChunked;

use strict;
use base 'Plugins::AirPlay::Chunked';

my $resp;
my $respii = 0;

sub new {
        my $class     = shift;
        my $responses = shift;

        my $self = $class->SUPER::new();
        $resp   = $responses;
        $respii = 0;

        return $self;
}

sub _sysread {

        #    my( $self, $socket, $buf, $size, $offset )= @_;
        printf("-------------------- Mock Sysread\n");

        #    return sysread($socket, $buf, $size, $offset );
        #    Copy( $xbuf, $buf, $size, $offset );
        my $preb = substr( $_[2], 0, $_[4] );
        my $newc = $$resp[ $respii++ ] || "";
        $_[2] = $preb . $newc;
        return length($newc);
}

1;
