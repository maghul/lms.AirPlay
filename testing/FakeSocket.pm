#!/bin/perl -w
package FakeSocket;

use base 'Slim::Networking::Async::Socket';

use IO::Scalar;

sub new {
        my $class  = shift;
        my $buffer = "";
        open FILE, "-|", "echo $buffer";
        my $fs = \*FILE;

        #    my $fs = IO::Scalar->new( \$buffer );

        bless $fs;

        $fs->set( "buf",     "" );
        $fs->set( "bufsize", 0 );
        return $fs;
}

## store data within the socket
#sub set {
#	my ( $self, $key, $val ) = @_;
#
#	$$self{$key} = $val;
#}
#
## pull data out of the socket
#sub get {
#	my ( $self, $key ) = @_;
#
#	return $$self{$key};
#}

sub close {
        my $self = shift;
}

1;
