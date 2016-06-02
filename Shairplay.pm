#
#   Interface to shairplay webcast server
#
package Plugins::AirPlay::Shairplay;

use strict;

use JSON::XS::VersionOneAndTwo;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string cstring);
use Plugins::AirPlay::HTTP;
use Plugins::AirPlay::Squeezebox;

my $log   = logger('plugin.airplay');
my $prefs = preferences('plugin.airplay');

#my $baseURL    = 'http://pollock';
my $baseURL = 'http://mauree:6111';

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

        # Timeout if we never get any data
        Slim::Utils::Timers::setTimer( $http, Time::HiRes::time() + $$data{RetryTimer}, \&reconnectNotifications, $data );
}

sub _tx {
        my $url = shift;
        $log->info( "AirPlay::Shairplay notification URL='" . $url . "'" );

        Plugins::AirPlay::HTTP->new()->send_request( { 'request' => HTTP::Request->new( GET => $url ), } );

}

sub command {
        my $command = shift;

        my $params;
        $log->info("AirPlay::Shairplay command '$command'");
        _tx("$baseURL/playah/control/$command");
}

sub jump {
        my $index = shift;
        command( $index > 0 ? "nextitem" : "previtem" );
}

sub play {
        my $index = shift;
        command( $index > 0 ? "nextitem" : "previtem" );
}

sub pause {
        my $index = shift;
        command( $index > 0 ? "nextitem" : "previtem" );
}

sub startNotifications {
        my $retryTimer    = shift || 3;
        my $maxRetryTimer = shift || 10;

        $retryTimer = $maxRetryTimer if ( $retryTimer > $maxRetryTimer );

        $log->info("AirPlay::Shairplay startNotifications retryTimer=$retryTimer, maxRetryTimer=$maxRetryTimer ");
        my $url = "$baseURL/notifications.json";
        $log->info( "AirPlay::Shairplay notification URL='" . $url . "'" );

        Plugins::AirPlay::HTTP->new()->send_request(
                {
                        'request'      => HTTP::Request->new( GET => $url ),
                        'onBody'       => \&asyncCBContent,
                        'onError'      => \&asyncCBContentTypeError,
                        'onDisconnect' => \&asyncDisconnect,
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
