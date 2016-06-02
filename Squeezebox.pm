#
#  Controls a squeezebox and server
#

package Plugins::AirPlay::Squeezebox;

use Data::Dumper;

use Slim::Utils::Log;

my $log = logger('plugin.airplay');

sub get_client() {

        $log->warn("GET CLIENT");
        foreach my $client ( Slim::Player::Client::clients() ) {
                if ( $client->name() =~ /Magnus Rum/ ) {

                        #	    $log->warn("\n !!!CLIENT: ".Data::Dump::dump($client));
                        return $client;
                }
        }
}

sub start_player() {
        $log->warn("START AirPlay squeezebox\n");
        my $client      = get_client();
        my $client_name = "whatever";

        if ($client) {
                $log->warn("STARTING AirPlay play\n");
                $client->execute( [ "playlist", "play", "http://mauree:6111/$client_name/audio.pcm" ] );
        }
}

sub stop_player() {
        $log->warn("STOP AirPlay squeezebox\n");
        my $client = get_client();
        if ($client) {
                $log->warn("STOPPING AirPlay play\n");
                $client->execute( ["stop"] );
        }
}

sub notification {
        my ($notification) = @_;

        $log->warn( "\nNotification\n" . Data::Dump::dump($notification) . "\nNotification\n" );
}

1;
