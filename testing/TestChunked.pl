#!/bin/perl -w
use Test::More tests => 90 * 4;

use common::sense;
no warnings;

use constant SLIM_SERVICE => 0;
use constant ISWINDOWS    => 0;
use constant ISMAC        => 0;
use constant PERFMON      => 0;
use constant SCANNER      => 0;
use constant LOCALFILE    => 0;
use constant WARNING_BITS => 0;

use constant DEBUGLOG => 0;
use constant INFOLOG  => 0;

use constant WEBUI => 0;

use constant VIDEO        => 0;
use constant MEDIASUPPORT => 0;
use constant IMAGE        => 0;

use Slim::Utils::OSDetect;
use FakeSocket;

Slim::Utils::OSDetect->init();
my $os = Slim::Utils::OSDetect->getOS;
print "OS is $os\n";

require "MockChunked.pm";

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($ERROR);

sub runSplitTest {
        my $sp = shift;
        print( "\n\n------  Starting test with split point at " . $sp . "  -------\n\n\n" );
        my $input = "HTTP/1.0 200 OK\r\n\r\n10\r\nHejsan Hoppsan!!\r\n06\r\nHoppla\r\n11\r\nFalle! Ralle! Ra?\r\n";

        my $bufs = [ substr( $input, 0, $sp ), substr( $input, $sp ), ];

        my $chunked = MockChunked->new($bufs);

        my $chunks = [];
        my $args   = {
                onConnect => sub {
                        my ( $chunked, $passthrough ) = @_;
                        printf("!!!!!!!!!!!!! onConnect\n");
                        push @$chunks, "HEADER";
                },
                onBody => sub {
                        my ( $chunked, $passthrough ) = @_;
                        my $data = $chunked->response->content;
                        printf("!!!!!!!!!!!!! onBody: $data\n");
                        push @$chunks, $data;
                  }
        };

        my $socket = FakeSocket::new($bufs);
        $chunked->content_parser( \&Plugins::AirPlay::Chunked::_parse_header );
        $chunked->socket($socket);
        $chunked->_http_read($args);

        is $$chunks[0], "HEADER";
        is $$chunks[1], "Hejsan Hoppsan!!";
        is $$chunks[2], "Hoppla";
        is $$chunks[3], "Falle! Ralle! Ra?";
}

my $split = 0;
if ($split) {
        runSplitTest($split);
}
else {
        my $ii;
        for ( $ii = 1 ; $ii < 91 ; ++$ii ) {
                runSplitTest($ii);
        }
}
