use strict;

use base qw(Test::Class);
use Test::More;
use Plugins::AirPlay::ChunkedHTTP;

sub mockContent {
        my $http    = shift;
        my $content = $http->response->content;
        print "mock content= $content\n";
}

sub mockContentError {
        my $http = shift;
        my $msg  = shift;

        print "mock content error: $msg\n";
}

sub mockDisconnect {
        print "mock disconnect\n";
}

sub mockConnect {
        print "mock connect\n";
}

sub fileToString {
        my $file = shift;

        open FILE, "$file" or die "Couldn't open file: $!";
        my $string = join( "", <FILE> );
        close FILE;
        return $string;

}

sub test_simple_request : Test(1) {

        #	Slim::Networking::Async::HTTP->init;

        my $url           = "http://127.0.0.1:8822/";
        my $retryTimer    = 100;
        my $maxRetryTimer = 10000;

        #	system("socat -T 1 -d  TCP-L:8822,reuseaddr,fork,crlf SYSTEM:\"cat testdata/test_simple_request.http\" &");
        #	sleep(1);

        my $ch;
        $ch = Plugins::AirPlay::tests::TestableChunkedHTTP->new();
        $ch->setTestdata( fileToString("testdata/test_simple_request.http") );
        print "ch=$ch\n";
        $ch->send_request(
                {
                        'request'      => HTTP::Request->new( GET => $url ),
                        'onChunk'      => \&mockContent,
                        'onError'      => \&mockContentError,
                        'onDisconnect' => \&mockDisconnect,
                        'onHeaders'    => \&mockConnect,
                        'Timeout'      => 100000000,
                        'passthrough'  => [
                                {
                                        'RetryTimer'    => $retryTimer,
                                        'MaxRetryTimer' => $maxRetryTimer
                                }
                        ]
                }
        );

}

package Plugins::AirPlay::tests::TestableChunkedHTTP;

use base "Plugins::AirPlay::ChunkedHTTP";

__PACKAGE__->mk_accessor( rw => 'data' );

sub setTestdata {
        my ( $self, $data ) = @_;

        print "setTestdata: $self\n";
        $self->data($data);
}

sub _sysread {

        #    my( $self, $socket, $buf, $size, $offset )= @_;
        my $self = $_[0];
        my $data = $self->data;
        $self->data(undef);
        $_[2] = $_[2] . $data;
        return length($data);
}

sub send_request {
        my ( $self, $req ) = @_;
        print "send_request\n";

        $self->socket( $self->new_socket );
        while ( defined $self->data ) {
                $self->_http_read($req);
        }
}

1;

