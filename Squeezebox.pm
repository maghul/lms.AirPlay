#
#  Controls a squeezebox and server
#

package Plugins::AirPlay::Squeezebox;

use Plugins::AirPlay::Shairplay;

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
        my $client_name = "00:11:22:33:44:55";    # TODO Use the real id

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

        if ( !$metadata ) {
                $metadata = {
                        artist => "",
                        album  => "",

                        bitrate => 44100,
                        type    => "AirPlay"
                };
        }
        print Data::Dump::dump($metadata);
        return $metadata;
}

sub dmap_lisitingitem_notification {
        my $dmap = shift;

        my $id = "00:11:22:33:44:55";    # TODO: Get the real Id

        my $trackurl = "http://mauree:6111/$id/audio.pcm";
        Slim::Music::Info::setRemoteMetadata( $trackurl, { title => $$dmap{'dmap.itemname'}, } );
        my $itemid = $$dmap{'dmap.persistentid'};
        my $obj    = Slim::Schema::RemoteTrack->updateOrCreate(
                $trackurl,
                {
                        title  => $$dmap{'dmap.itemname'},
                        artist => $$dmap{'daap.songartist'},
                        album  => $$dmap{'daap.songalbum'},

                        #		secs    => $track->{'duration'} / 1000,
                        coverurl => "airplayimage/$id/cover.$itemid.jpg",
                        tracknum => $$dmap{'daap.songtracknumber'},
                        bitrate  => 44100,
                }
        );

        $metadata = {
                artist => $$dmap{'daap.songartist'},
                album  => $$dmap{'daap.songalbum'},

                coverurl => "airplayimage/$id/cover.$itemid.jpg",
                tracknum => $$dmap{'daap.songtracknumber'},
                bitrate  => 44100,
                type     => "AirPlay"
        };

        $log->debug( "Playing info: " . Data::Dump::dump($obj) );

}

sub airplay_to_squeezebox_volume {
        my $volume = shift;
        return 100 + ( $volume * 100.0 / 30.0 );
}

sub squeezebox_to_airplay_volume {
        my $volume = shift;
        return -144 if ( $volume == 0 );
        return -30 + $volume * 30 / 100;
}

my $sb_volume;
my $target_volume;

sub volume_notification {
        my $volume = shift;

        $log->debug("Volume=$volume\n");
        my $client = get_client();

        my $new_volume = airplay_to_squeezebox_volume($volume);
        $new_volume = 0 if ( $sb_volume < 0 );

        if ( defined $target_volume ) {
                $log->debug("new_volume=$new_volume, target_volume=$target_volume, sb_volume=$sb_volume\n");

                if (       ( $new_volume <= $target_volum && $target_volume <= $sb_volume )
                        || ( $new_volume <= $target_volum && $target_volume <= $sb_volume ) )
                {
                        undefine $target_volume;
                }
                else {
                        changeVolume();
                }
        }
        else {
                $client->execute( [ "mixer", "volume", $sb_volume ] );
        }
        $sb_volume = $new_volume;
}

sub changeVolume {
        if ($target_volume) {
                my $vol = $target_volume < $sb_volume ? "volumedown" : "volumeup";
                Plugins::AirPlay::Shairplay::command($vol);
        }
}

sub mixerVolumeCallback {
        my $request = shift;
        my $client  = $request->client;

        return if !defined $client;

        # TODO: Check if it running airplay.

        my $volume = $client->volume();

        $log->debug("mixer volume=$volume");

        $target_volume = $volume;
        changeVolume();
}

sub notification {
        my ($notification) = @_;

        $log->warn( "\nNotification\n" . Data::Dump::dump($notification) . "\nNotification\n" );

        my $content = $$notification{"00:11:22:33:44:55"};
        my $dmap    = $$content{"dmap.listingitem"};
        dmap_lisitingitem_notification($dmap) if ($dmap);

        my $volume = $$content{"volume"};
        volume_notification($volume) if ( defined $volume );
}

1;
