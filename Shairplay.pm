#
#   Interface to shairplay webcast server
#
package Plugins::AirPlay::Shairplay;

use strict;

use JSON::XS::VersionOneAndTwo;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string cstring);
use Slim::Networking::Async::HTTP;
use Plugins::AirPlay::ChunkedHTTP;
use Plugins::AirPlay::Squeezebox;
use Plugins::AirPlay::Squeezeplay;

my $log   = logger('plugin.airplay');
my $prefs = preferences('plugin.airplay');

my $baseUrl = Plugins::AirPlay::Squeezeplay::getBaseUrl();

my $sessions_running = 0;
my $sequenceNumber   = -1;

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
                                $log->info("Shairplay notification sequence number mismatch: expected $sequenceNumber but got $seq");
                        }
                        $sequenceNumber = $seq + 0;
                }
        }

        $log->warn( Data::Dump::dump($data) );
        eval {
                my $perl = decode_json($html);
                Plugins::AirPlay::Squeezebox::notification($perl);
        };

        if ($@) {
                $log->warn( "Shairplay message could not be decoded, shutting down notifications." . $@ );
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
        Plugins::AirPlay::Squeezeplay::checkHelper();
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
                command( $client, $index > 0 ? "nextitem" : "previtem" );
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

        $log->info("AirPlay::Shairplay startNotifications retryTimer=$retryTimer, maxRetryTimer=$maxRetryTimer ");
        my $url = "$baseUrl/notifications.json";
        $log->info( "AirPlay::Shairplay notification URL='" . $url . "'" );

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
        $log->info( "AirPlay::Shairplay start session URL='" . $url . "'" );

        my $request = HTTP::Request->new( GET => $url );
        $request->header( "airplay-session-id",   $id );
        $request->header( "airplay-session-name", $name );
        Slim::Networking::Async::HTTP->new()->send_request( { 'request' => $request } );
}

sub stopSession {
        my ($client) = @_;

        my $id   = $client->id();
        my $name = $client->name();

        my $url = "$baseUrl/control/stop";
        $log->info( "AirPlay::Shairplay stop session URL='" . $url . "'" );

        my $request = HTTP::Request->new( GET => $url );
        $request->header( "airplay-session-id",   $id );
        $request->header( "airplay-session-name", $name );
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
