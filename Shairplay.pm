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
use Plugins::AirPlay::Chunked;
use Plugins::AirPlay::Squeezebox;

my $log   = logger('plugin.airplay');
my $prefs = preferences('plugin.airplay');

my $baseURL = 'http://localhost:6111';

my $sessions_running = 0;

sub asyncCBContentType {
        my ( $http, $client, $params, $callback, $httpClient, $response ) = @_;
        $log->warn( Data::Dump::dump($http) );
        return 1;
}

sub asyncCBContent {
        my $http = shift;
        my $data = shift;
        $$data{RetryTimer} = 1;
        my $html = $http->response->content();
        $log->warn( Data::Dump::dump($html) );
        $log->warn( Data::Dump::dump($data) );
        my $perl = decode_json($html);

        #    $log->warn(Data::Dump::dump($perl));

        Plugins::AirPlay::Squeezebox::notification($perl);
        return 1;
}

sub asyncCBContentTypeError {

        # error callback for establishing content type - causes indexHandler to be processed again with stored params
        my ( $http, $error, $client, $params, $callback, $httpClient, $response ) = @_;
        $sessions_running = 0;    # Restart sessions on reconnect?
}

sub reconnectNotifications {
        my ( $error, $data ) = @_;

        $log->warn("reconnectNotifications. trying again... ");

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

sub _tx {
        my $url      = shift;
        my $callback = shift;
        $log->info( "EMH tx URL='" . $url . "'" );

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
        $log->info("AirPlay::Shairplay client '$client->name()', command '$command'");
        _tx( "$baseURL/$player/control/$command", $callback );
}

sub jump {
        my $client = shift;
        my $index  = shift;
        command( $client, $index > 0 ? "nextitem" : "previtem" );
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

        _tx("$baseURL/control/notify");
}

sub startNotifications {
        my $retryTimer    = shift || 3;
        my $maxRetryTimer = shift || 10;

        $retryTimer = $maxRetryTimer if ( $retryTimer > $maxRetryTimer );

        $log->info("AirPlay::Shairplay startNotifications retryTimer=$retryTimer, maxRetryTimer=$maxRetryTimer ");
        my $url = "$baseURL/notifications.json";
        $log->info( "AirPlay::Shairplay notification URL='" . $url . "'" );

        Plugins::AirPlay::Chunked->new()->send_request(
                {
                        'request'      => HTTP::Request->new( GET => $url ),
                        'onBody'       => \&asyncCBContent,
                        'onError'      => \&asyncCBContentTypeError,
                        'onDisconnect' => \&asyncDisconnect,
                        'onConnect'    => \&asyncConnect,
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

        my $url = "$baseURL/control/start";
        $log->info( "AirPlay::Shairplay start session URL='" . $url . "'" );

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
                }
        }
}

1;
