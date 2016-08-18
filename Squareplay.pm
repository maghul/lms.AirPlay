#
#  Manage the squareplay daemon.
#
package Plugins::AirPlay::Squareplay;

use strict;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Network;
use Slim::Utils::Strings qw(string cstring);

use Slim::Networking::Async::HTTP;

use Proc::Background;
use File::ReadBackwards;
use File::Spec::Functions;
use JSON::XS::VersionOneAndTwo;
use Config;

use HTTP::Request;
use Plugins::AirPlay::ChunkedHTTP;
use Plugins::AirPlay::Squeezebox;

my $squareplay;
my $log = logger('plugin.airplay');

sub new {
        my $class = shift;

        my $self = {};

        return bless( $self, $class );

}

sub logFile {
        return catdir( Slim::Utils::OSDetect::dirsFor('log'), "squareplay.log" );
}

sub start {
        my $self       = shift;
        my $helper     = "squareplay";
        my $helperName = Slim::Utils::Misc::findbin($helper) || do {
                $log->debug("helper app: $helper not found");
                return;
        };
        my $helperPath = Slim::Utils::OSDetect::getOS->decodeExternalHelperPath($helperName);
        my $logfile    = logFile();

        $squareplay = undef;
        my $cmd = $helperPath;
        $log->info("starting $cmd");

        eval { $squareplay = Proc::Background->new( { 'die_upon_destroy' => 1 }, $cmd ); };
        $log->info("started $cmd $squareplay");
}

sub checkHelper {
        my $self       = shift;
        $log->info("Helper app check");
        if ( defined $squareplay ) {
                $log->info("Helper app exists");
                if ( !$squareplay->alive ) {
                        $log->info("Helper daemon is not running. Will restart");
                        $self->start();
                }
        }
}

# ---------------------  Interface to plugin -------------------------------
my $sessions_running = 0;
my $sequenceNumber   = -1;

my $baseurl;

sub uri {
        my $class = shift;
        my $request = shift || '';

        if ( !defined $baseurl ) {
                my $hostname = Slim::Utils::Network::serverAddr();
                $baseurl = "http://$hostname:6111";
        }

        my $uri = "$baseurl/$request";
        return $uri;
}

sub asyncCBContent {
        my $http = shift;
        my $data = shift;
        $$data{RetryTimer} = 1;
        my $html = $http->response->content();
        $log->debug( "HTML Chunk: " . Data::Dump::dump($html) );
        my $seq = $http->response->header("chunk_extensions");

        if ( defined $seq ) {
                $seq =~ s/seq=//;
                $seq += 0;
                if ( ++$sequenceNumber != $seq ) {
                        if ( $sequenceNumber != -1 ) {
                                $log->info("Squareplay notification sequence number mismatch: expected $sequenceNumber but got $seq");
                        }
                        $sequenceNumber = $seq + 0;
                }
        }

        eval {
                my $perl = decode_json($html);
                my $dump = Data::Dump::dump($perl);
                $dump =~ s/\n/\n                                                                          RX:/g;
                $log->debug( "RX: " . $dump );
                Plugins::AirPlay::Squeezebox::notification($perl);
        };

        if ($@) {
                $log->warn( "Squareplay message could not be decoded, shutting down notifications." . $@ );
                asyncDisconnect( $http, $data );
                return 0;
        }
        return 1;
}

sub asyncCBContentTypeError {
        my $http  = shift;
        my $error = shift;
        my $data  = shift;
        $log->warn("Notifications socket error: $error");

        asyncDisconnect( $http, $data );
}

sub asyncDisconnect {
        my $http = shift;
        my $data = shift;

        my $squareplay = $$data{Squareplay};

        $log->warn("Notifications disconnecting. Will try again... ");
        $sessions_running = 0;    # Restart sessions on reconnect?

        # Timeout if we never get any data
	$$data{RetryTimer} *= 2;
	if ($$data{RetryTimer}>$$data{MaxRetryTimer}) {
		$$data{RetryTimer}= $$data{MaxRetryTimer};
	}
        Slim::Utils::Timers::setTimer( $squareplay, Time::HiRes::time() + $$data{RetryTimer}, \&reconnectNotifications, $data );
}

sub asyncConnect {
        my $http = shift;
        my $data = shift;

        my $squareplay = $$data{Squareplay};

        $log->info("Notifications Connected. ");
        $squareplay->startAllSessions();
}

sub nop_callback {
##    $log->debug( "nop_callback..." );
}

sub reconnectNotifications {
        my ( $self, $data ) = @_;

        $log->warn("reconnectNotifications. trying again... ");
        $sequenceNumber = -1;
        $self->checkHelper();
        $self->_startNotifications( $data );
}

sub _tx {
        my $self     = shift;
        my $url      = shift;
        my $callback = shift || \&nop_callback;
        $log->debug("TX URL='$url'");

        Slim::Networking::SimpleAsyncHTTP->new( $callback, $callback )->get($url);
}

sub post_request {
        my $self    = shift;
        my $req     = shift;
        my $content = shift;
        my $callback = shift || \&nop_callback;
        my $ecallback = shift || \&nop_callback;

        my $url = $self->uri($req);
        $log->debug("TX URL='$url', POST content=$content");

	

        Slim::Networking::SimpleAsyncHTTP->new( $callback, $ecallback )->post($url,$content);
}

sub setClientNotificationState {
        my $self = shift;

        $self->_tx( $self->uri("control/notify") );
}

sub startNotifications {
        my $self = shift;

        my $retryTimer    = shift || 3;
        my $maxRetryTimer = shift || 10;

        $retryTimer = $maxRetryTimer if ( $retryTimer > $maxRetryTimer );

	my $data = {
		'Squareplay'    => $self,
		'RetryTimer'    => $retryTimer,
		'MaxRetryTimer' => $maxRetryTimer
	};

        $log->info("AirPlay::Squareplay startNotifications retryTimer=$retryTimer, maxRetryTimer=$maxRetryTimer ");
        Slim::Utils::Timers::setTimer( $self, Time::HiRes::time() + $retryTimer, \&_startNotifications, $data );
}

sub _startNotifications {
        my $self = shift;
	my $data = shift;
	
        my $url = $self->uri("notifications.json");
        $log->info( "AirPlay::Squareplay notification URL='" . $url . "'" );

        Plugins::AirPlay::ChunkedHTTP->new()->send_request(
                {
                        'request'      => HTTP::Request->new( GET => $url ),
                        'onChunk'      => \&asyncCBContent,
                        'onError'      => \&asyncCBContentTypeError,
                        'onDisconnect' => \&asyncDisconnect,
                        'onHeaders'    => \&asyncConnect,
                        'Timeout'      => 100000000,
                        'passthrough'  => $data,
                }
        );

}

sub stopNotifications {

        # NYI
}

sub startAllSessions {
        my $self = shift;

        $log->debug("Start All Sessions sessions_running=$sessions_running");
        if ( !$sessions_running ) {
                $sessions_running = 1;
                foreach my $client ( Slim::Player::Client::clients() ) {
                        $log->debug( "Start Session client name=" . $client->name() . ", id=" . $client->id() );
                        my $box = Plugins::AirPlay::Squeezebox->getOrCreate( $client, $self );
			$box->sendStart();
			$box->getexternalvolumeinfo();
                }

        }
}

1;
