#
#   Interface to shairplay webcast server
#
package Plugins::AirPlay::Shairplay;

use strict;

use JSON::XS::VersionOneAndTwo;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string cstring);
use Plugins::AirPlay::HTTP;    # Actually Slim::Networking::Async::HTTP

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

        #    my $html = shift;
        #    $log->warn(Data::Dump::dump($http));
        my $html = $http->response->content();
        $log->warn( Data::Dump::dump($html) );
        my $perl = decode_json($html);
        $log->warn( Data::Dump::dump($perl) );

        return 1;
}

sub asyncCBContentTypeError {

        # error callback for establishing content type - causes indexHandler to be processed again with stored params
        my ( $http, $error, $client, $params, $callback, $httpClient, $response ) = @_;
        logBacktrace("asyncCBContentTypeError");
        $log->warn( Data::Dump::dump($http) );
        $log->warn( Data::Dump::dump($error) );
        $log->warn( Data::Dump::dump(@_) );
}

sub gotNotification {
        my $http = shift;
        my $buf  = shift;

        #	my $html = $http->content();
        #	my $params = $http->params();
        $log->warn("Shairplay: gotNotification");
        $log->warn( Data::Dump::dump($http) );
        $log->warn( Data::Dump::dump($buf) );

        #	$log->warn("content=".$html."--content-end--");
}

sub startNotifications {
        my $params;
        $log->info("AirPlay::Shairplay startNotifications");
        my $url = "$baseURL/notifications.json";
        $log->info( "AirPlay::Shairplay notification URL='" . $url . "'" );

        Plugins::AirPlay::HTTP->new()->send_request(
                {
                        'request' => HTTP::Request->new( GET => $url ),

                        #	'onHeaders'   => \&asyncCBContentType,
                        #	'onStream'   => \&asyncCBContent,
                        'onBody'  => \&asyncCBContent,
                        'onError' => \&asyncCBContentTypeError,
                        'Timeout' => 100000000,

                        #	'passthrough' => [ $client, $params, @_ ],
                }
        );

}
