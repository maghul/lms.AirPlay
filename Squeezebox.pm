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

local $metadata;

sub metaDataProvider {
        my ( $client, $url ) = @_;

        print Data::Dump::dump($metadata);
        return $metadata;
}

sub dmap_lisitingitem_notification {
        my ($notification) = @_;

        $log->warn( "\nNotification\n" . Data::Dump::dump($notification) . "\nNotification\n" );

        my $trackurl = "http://mauree:6111/whatever/audio.pcm";
        Slim::Music::Info::setRemoteMetadata( $trackurl, { title => $$dmap{'dmap.itemname'}, } );
        my $itemid = $$dmap{'dmap.persistentid'};
        my $obj    = Slim::Schema::RemoteTrack->updateOrCreate(
                $trackurl,
                {
                        title  => $$dmap{'dmap.itemname'},
                        artist => $$dmap{'daap.songartist'},
                        album  => $$dmap{'daap.songalbum'},

                        #		secs    => $track->{'duration'} / 1000,
                        coverurl => "airplayimage/whatever/cover.$itemid.jpg",
                        tracknum => $$dmap{'daap.songtracknumber'},
                        bitrate  => 44100,
                }
        );

        $metadata = {
                artist => $$dmap{'daap.songartist'},
                album  => $$dmap{'daap.songalbum'},

                coverurl => "airplayimage/whatever/cover.$itemid.jpg",
                tracknum => $$dmap{'daap.songtracknumber'},
                bitrate  => 44100,
                type     => "AirPlay"
        };

        $log->debug( "Playing info: " . Data::Dump::dump($obj) );

}

sub volume_notification {
        my $volume = shift;

        $log->debug("Volume=$volume\n");
        my $client = get_client();
        my $sb_volume = 100 + ( $volume * 100.0 / 30.0 );
        $sb_volume = 0 if ( $sb_volume < 0 );
        $client->execute( [ "mixer", "volume", $sb_volume ] );
}

sub notification {
        my ($notification) = @_;

        $log->warn( "\nNotification\n" . Data::Dump::dump($notification) . "\nNotification\n" );

        my $dmap = $$notification{"dmap.listingitem"};
        dmap_lisitingitem_notification($dmap) if ($dmap);

        my $volume = $$notification{"volume"};
        volume_notification($volume) if ( defined $volume );
}

1;
