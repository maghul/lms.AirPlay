#
#  Manage the squareplay daemon.
#
package Plugins::AirPlay::Squareplay;

use strict;

use Slim::Utils::Log;
use Slim::Utils::Network;

use Proc::Background;
use File::ReadBackwards;
use File::Spec::Functions;
use JSON::XS::VersionOneAndTwo;
use Config;

my $squareplay;
my $log = logger('plugin.airplay');

sub logFile {
        return catdir( Slim::Utils::OSDetect::dirsFor('log'), "squareplay.log" );
}

sub start {
        my $helper = "squareplay";
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
        $log->info("Helper app check");
        if ( defined $squareplay ) {
                $log->info("Helper app exists");
                if ( !$squareplay->alive() ) {
                        $log->info("Helper daemon is not running. Will restart");
                        start();
                }
        }
}

my $baseurl;

sub getBaseUrl() {
        if ( !defined $baseurl ) {

                #		my $hostname= Slim::Utils::Network::hostAddr();
                # TODO: Must fix this!
                my $hostname = "10.223.10.35";
                $baseurl = "http://$hostname:6111";
        }
        return $baseurl;
}

# ---------------------  Interface to plugin -------------------------------
my $sessions_running = 0;
my $sequenceNumber   = -1;
my $baseUrl          = getBaseUrl();

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

sub reconnectNotifications {
        my ( $http, $data ) = @_;

        $log->warn("reconnectNotifications. trying again... ");
        $sequenceNumber = -1;
        Plugins::AirPlay::Squareplay::checkHelper();
        startNotifications( $$data{RetryTimer} * 2, $$data{MaxRetryTimer} );
}

sub asyncDisconnect {
        my $http = shift;
        my $data = shift;

        $log->warn("Notifications disconnecting. Will try again... ");
        $sessions_running = 0;    # Restart sessions on reconnect?

        # Timeout if we never get any data
        Slim::Utils::Timers::setTimer( $http, Time::HiRes::time() + $$data{RetryTimer}, \&reconnectNotifications, $data );
}

sub asyncConnect {
        my $http = shift;
        my $data = shift;

        $log->info("Notifications Connected. ");
        startAllSessions();
}

sub nop_callback {
##    $log->debug( "nop_callback..." );
}

sub _tx {
        my $url = shift;
        my $callback = shift || \&nop_callback;
        $log->debug("TX URL='$url'");

        Slim::Networking::SimpleAsyncHTTP->new( $callback, $callback )->get($url);

        #    Slim::Networking::Async::HTTP->new()->send_request( {
        #	'request'     => HTTP::Request->new( GET => $url ),
        #	'onBody' => $callback,
        #	'onError' => $callback,
        #    } );

}

sub command {
        my $client   = shift;
        my $command  = shift;
        my $callback = shift;
        my $player   = $client->id();

        my $params;
        $log->info( $client->name() . ": command '$command'" );
        _tx( "$baseUrl/$player/control/$command", $callback );
}

sub jump {
        my $client = shift;
        my $index  = shift;
        if ( $index != 0 ) {
                command( $client, "pause" );
                command( $client, $index > 0 ? "nextitem" : "previtem" );
                command( $client, "playresume" );
        }
}

#sub play {
#    my $client= shift;
#    my $index= shift;
#    command( $client, $index>0?"nextitem":"previtem");
#}
#
#sub pause {
#    my $client= shift;
#    my $index= shift;
#    command( $client, $index>0?"nextitem":"previtem");
#}

sub setClientNotificationState {
        my $client = shift;

        _tx("$baseUrl/control/notify");
}

sub startNotifications {
        my $retryTimer    = shift || 3;
        my $maxRetryTimer = shift || 10;

        $retryTimer = $maxRetryTimer if ( $retryTimer > $maxRetryTimer );

        $log->info("AirPlay::Squareplay startNotifications retryTimer=$retryTimer, maxRetryTimer=$maxRetryTimer ");
        my $url = "$baseUrl/notifications.json";
        $log->info( "AirPlay::Squareplay notification URL='" . $url . "'" );

        Plugins::AirPlay::ChunkedHTTP->new()->send_request(
                {
                        'request'      => HTTP::Request->new( GET => $url ),
                        'onChunk'      => \&asyncCBContent,
                        'onError'      => \&asyncCBContentTypeError,
                        'onDisconnect' => \&asyncDisconnect,
                        'onHeaders'    => \&asyncConnect,
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

sub stopNotifications {

        # NYI
}

sub startSession {
        my ($client) = @_;

        my $id   = $client->id();
        my $name = $client->name();

        my $url = "$baseUrl/control/start";
        $log->info( "AirPlay::Squareplay start session URL='" . $url . "'" );

        my $request = HTTP::Request->new( POST => $url );
        my $request->content("[{\"id\":\"$id\",\"name\":\"$name\"}]");

        #    $request->header( "airplay-session-id", $id );
        #    $request->header( "airplay-session-name", $name );
        #    $log->debug("TX URL='$url', airplay-session-id='$id', airplay-session-name='$name'");
        Slim::Networking::Async::HTTP->new()->send_request( { 'request' => $request } );
}

sub stopSession {
        my ($client) = @_;

        my $id   = $client->id();
        my $name = $client->name();

        my $url = "$baseUrl/control/stop";
        $log->info( "AirPlay::Squareplay stop session URL='" . $url . "'" );

        my $request = HTTP::Request->new( GET => $url );
        $request->header( "airplay-session-id",   $id );
        $request->header( "airplay-session-name", $name );
        $log->debug("TX URL='$url', airplay-session-id='$id', airplay-session-name='$name'");

        Slim::Networking::Async::HTTP->new()->send_request( { 'request' => $request } );
}

sub startAllSessions {
        $log->debug("Start All Sessions sessions_running=$sessions_running");
        if ( !$sessions_running ) {
                $sessions_running = 1;
                foreach my $client ( Slim::Player::Client::clients() ) {
                        $log->debug( "Start Session client name=" . $client->name() . ", id=" . $client->id() );
                        Plugins::AirPlay::Squeezebox::initClient($client);
                        startSession($client);
                        Plugins::AirPlay::Squeezebox::send_volume_control_state($client);
                }
        }
}

1;
