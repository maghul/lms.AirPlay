#
#  Controls a squeezebox and server
#

package Plugins::AirPlay::Squeezebox;

use Plugins::AirPlay::Shairplay;

use Data::Dumper;

use Slim::Utils::Log;

my $log = logger('plugin.airplay');

sub start_player {
        $log->warn("START AirPlay squeezebox\n");
        my $client = shift;

        if ($client) {
                my $client_id = $client->id();
                $log->warn("STARTING AirPlay play\n");
                $client->execute( [ "playlist", "play", "http://mauree:6111/$client_id/audio.pcm" ] );
        }
}

sub stop_player {
        $log->warn("STOP AirPlay squeezebox\n");
        my $client = shift;
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
        my $client = shift;
        my $dmap   = shift;

        my $trackurl = "http://mauree:6111/$id/audio.pcm";
        Slim::Music::Info::setRemoteMetadata( $trackurl, { title => $$dmap{'dmap.itemname'}, } );
        my $itemid        = $$dmap{'dmap.persistentid'};
        my $squeezebox_id = $client->id();
        my $obj           = Slim::Schema::RemoteTrack->updateOrCreate(
                $trackurl,
                {
                        title  => $$dmap{'dmap.itemname'},
                        artist => $$dmap{'daap.songartist'},
                        album  => $$dmap{'daap.songalbum'},

                        #		secs    => $track->{'duration'} / 1000,
                        coverurl => "airplayimage/$id/$squeezebox_id/cover.$itemid.jpg",
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

sub between {
        my ( $a, $middle, $b ) = @_;

        if ( $a <= $middle && $middle <= $b ) {
                $log->debug("between... $a <= $middle <= $b\n");
                return 1;
        }
        if ( $a >= $middle && $middle >= $b ) {
                $log->debug("between... $a >= $middle >= $b\n");
                return 1;
        }

        $log->debug("NOT between... $a .. $middle .. $b\n");
        return 0;
}

sub volume_notification {
        my $client = shift;
        my $volume = shift;

        $log->debug("Volume=$volume\n");

        my $new_volume = airplay_to_squeezebox_volume($volume);
        $new_volume = 0 if ( $sb_volume < 0 );

        if ( defined $target_volume ) {
                $log->debug("new_volume=$new_volume, target_volume=$target_volume, sb_volume=$sb_volume\n");

                if ( between( $new_volume, $target_volume, $sb_volume ) ) {
                        $log->debug("------ Done!\n");
                        $sb_volume = $new_volume;
                        undef $target_volume;
                }
                else {
                        $log->debug("------ Change Volume!\n");
                        $sb_volume = $new_volume;
                        changeVolume($client);
                }
        }
        else {
                $client->execute( [ "mixer", "volume", $sb_volume ] );
        }
}

sub changeVolume {
        my $client = shift;

        if ($target_volume) {
                $log->debug("changeVolume: target_volume=$target_volume, sb_volume=$sb_volume\n");

                my $vol = $target_volume < $sb_volume ? "volumedown" : "volumeup";
                Plugins::AirPlay::Shairplay::command( $client, $vol );
        }
}

sub mixerVolumeCallback {
        my $request = shift;
        my $client  = $request->client;

        return if !defined $client;

        # TODO: Check if it running airplay.

        my $volume = $client->volume();

        $log->debug("mixer volume=$volume");

        $target_volume = $volume + 0;
        changeVolume();
}

sub externalVolumeInfoCallback {
        my $request = shift;
        my $client  = $request->client;

        if ($client) {
                my $relative = $request->getParam('_p1');
                my $precise  = $request->getParam('_p2');
                $log->debug( "client=" . $client->name() . ", id=" . $client->id() . ", relative=$relative, precise=$precise" );
        }
}

sub find_client {
        my $id = shift;

        $log->warn("GET CLIENT");
        foreach my $client ( Slim::Player::Client::clients() ) {
                $log->debug( "GET CLIENT name=" . $client->name() . ", id=" . $client->id() );
                if ( $client->id() eq $id ) {
                        return $client;
                }
        }
        return undef;
}

sub notification {
        my ($notification) = @_;

        $log->warn( "\nNotification\n" . Data::Dump::dump($notification) . "\nNotification\n" );

        while ( ( $key, $value ) = each %$notification ) {
                $log->debug("key: '$key', value: $hash{$key}\n");
                my $client = find_client($key);
                $log->debug("client is $client");
                if ($client) {
                        $log->debug( "client is " . $client->name() );

                        my $content = $value;
                        my $dmap    = $$content{"dmap.listingitem"};
                        dmap_lisitingitem_notification( $client, $dmap ) if ($dmap);

                        my $volume = $$content{"volume"};
                        volume_notification( $client, $volume ) if ( defined $volume );
                }
                else {
                        $log->debug("No client named '$key' yet....");
                }
        }
}

1;
