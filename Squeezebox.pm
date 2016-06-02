#
#  Controls a squeezebox and server
#

package Plugins::AirPlay::Squeezebox;

use Plugins::AirPlay::Shairplay;
use Plugins::AirPlay::Squeezeplay;

use Data::Dumper;

use Slim::Utils::Log;

my $log     = logger('plugin.airplay');
my $baseUrl = Plugins::AirPlay::Squeezeplay::getBaseUrl();

my $client_info;

my $clientinfo = {};

sub initClient {
        my $client = shift;

        $$client_info{$client} = {};
}

sub getinfo {
        my $client = shift;

        $log->debug( "client=" . $client );
        $log->debug( "client=" . $client->name() . ", id=" . $client->id() );

        my $id = $client->id();
        $$clientinfo{$id} = {} if ( !exists $$clientinfo{$id} );

        return $$clientinfo{$id};
}

sub start_player {
        $log->warn("START AirPlay squeezebox\n");
        my $client = shift;

        if ($client) {
                my $client_id = $client->id();
                $log->warn("STARTING AirPlay play\n");
                $client->execute( [ "playlist", "play", "$baseUrl/$client_id/audio.pcm" ] );
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

sub metaDataProvider {
        my ( $client, $url ) = @_;

        if ( !$$client_info{$client}{metadata} ) {
                $$client_info{$client}{metadata} = {
                        artist => "",
                        album  => "",

                        bitrate => 44100,
                        type    => "AirPlay"
                };
        }
        print Data::Dump::dump( $$client_info{$client}{metadata} );
        return $$client_info{$client}{metadata};
}

sub dmap_lisitingitem_notification {
        my $client = shift;
        my $dmap   = shift;

        my $trackurl = "$baseUrl/$id/audio.pcm";
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

        $$client_info{$client}{metadata} = {
                artist => $$dmap{'daap.songartist'},
                album  => $$dmap{'daap.songalbum'},

                coverurl => "airplayimage/$id/cover.$itemid.jpg",
                tracknum => $$dmap{'daap.songtracknumber'},
                bitrate  => 44100,
                type     => "AirPlay"
        };

        $log->debug( "Playing info: " . Data::Dump::dump($obj) );

}

sub progress_notification {
        my $client   = shift;
        my $progress = shift;

        my $song    = $client->streamingSong;
        my $newtime = $$progress{current} / 1000;
        my $length  = $$progress{length} / 1000;

        #	start_player($client); # Might flush?
        $log->debug(" setting offset=$newtime, duration=$length");
        $song->startOffset($newtime);

        #	$song->startOffset($newtime-$client->songElapsedSeconds());
        $song->duration($length);
        $log->debug( "$name: song=" . $song->duration );

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

my $center_volume = 52;

sub _volumeCallback {
        $volumeChangePending = 0;
}

sub _changeVolume {
        my $client = shift;

        if ($target_volume) {
                my $vol = $target_volume < $sb_volume ? "volumedown" : "volumeup";
                $log->debug("changeVolume:EMH: client=$client, target_volume=$target_volume, sb_volume=$sb_volume ==> $vol\n");

                #		if ( ! $volumeChangePending ) {
                #			$volumeChangePending= 1;
                Plugins::AirPlay::Shairplay::command( $client, $vol, \&_volumeCallback );

                #		}
        }
}

sub _check_volume_reached {

        # Check if the target volume has been passed.
        my $volume      = shift;
        my $prev_volume = shift;

        my $rv = ( $prev_volume > $volume && $volume <= $target_volume )
          || ( $prev_volume < $volume && $volume >= $target_volume );

        $log->debug("EMH _check_volume_reached target_volume=$target_volume, volume=$volume, prev_volume=$prev_volume --> $rv\n ");

        return $rv;
}

sub setAirPlayDeviceVolume {
        my $client = shift;
        my $volume = shift;

        my $start = !defined $target_volume;

        $target_volume = $volume;
        $log->debug("EMH setAirPlayDeviceVolume target_volume=$target_volume, start=$start");
        if ($start) {
                _changeVolume($client);
        }
}

sub relative_volume_notification {
        my $client      = shift;
        my $volume      = shift;
        my $prev_volume = shift;

        $log->debug("EMH volume=$volume, prev_volume=$prev_volume");
        if ( $volume > $prev_volume && $prev_volume > 50 ) {
                $log->debug("EMH squeezebox volume +2");
                $client->execute( [ "mixer", "volume", "+2" ] );
        }
        if ( $volume < $prev_volume && $prev_volume < 50 ) {
                $log->debug("EMH squeezebox volume -2");
                $client->execute( [ "mixer", "volume", "-2" ] );
        }

        $target_volume = 50;

        #	if ( $volume<$target_volume-3 || $volume>$target_volume+3 ) {
        if ( between( $volume, $target_volume, $prev_volume ) ) {
                undef $target_volume;
        }
        else {
                _changeVolume($client);
        }

        #	}
}

sub relativeMixerVolumeCallback {
        my $request = shift;
        my $client  = $request->client;

        #	setAirPlayDeviceVolume($client, 50);
}

sub absolute_volume_notification {
        my $client      = shift;
        my $volume      = shift;
        my $prev_volume = shift;

        if ( defined $target_volume ) {
                $log->debug("EMH new_volume=$new_volume, target_volume=$target_volume, sb_volume=$sb_volume\n");

                if ( between( $volume, $target_volume, $prev_volume ) ) {
                        $log->debug("------ Done!\n");

                        #			$sb_volume= $new_volume;
                        undef $target_volume;
                }
                else {
                        $log->debug("------ Change Volume!\n");

                        #			$sb_volume= $new_volume;
                        _changeVolume($client);
                }
        }
        else {
                $log->debug("EMH Absolute Mixer volume $sb_volume!");
                $client->execute( [ "mixer", "volume", $sb_volume ] );
        }
}

sub absoluteMixerVolumeCallback {
        my $request = shift;
        my $client  = $request->client;

        my $volume = $client->volume();

        $log->debug("EMH: mixer volume=$volume");
        setAirPlayDeviceVolume( $client, $volume + 0 );
}

sub volume_notification {
        my $client   = shift;
        my $volume   = shift;
        my $relative = 1;

        my $prev_volume = $sb_volume;
        $sb_volume = airplay_to_squeezebox_volume($volume);

        my $info = getinfo($client);
        if ( $info{relative} ) {
                relative_volume_notification( $client, $sb_volume, $prev_volume );
        }
        else {
                absolute_volume_notification( $client, $sb_volume, $prev_volume );
        }

}

sub mixerVolumeCallback {
        my $request  = shift;
        my $client   = $request->client;
        my $relative = 1;

        return if !defined $client;
        $log->debug( "getinfo... client=" . $client );
        my $info = getinfo($client);
        if ( $info{relative} ) {
                relativeMixerVolumeCallback( $request, $client );
        }
        else {
                absoluteMixerVolumeCallback( $request, $client );
        }
}

# TODO: We should get the callback when prefs are changed but that doesn't seem to happen...
sub externalVolumeInfoCallback {
        my $request = shift;
        my $client  = $request->client;

        if ($client) {
                my $relative = $request->getParam('_p1');
                my $precise  = $request->getParam('_p2');
                $log->debug( "client=" . $client->name() . ", id=" . $client->id() . ", relative=$relative, precise=$precise" );

                $log->debug( "getinfo... client=" . $client );
                my $info = getinfo($client);
                $info{relative} = $relative;
                $info{precise}  = $precise;
        }
}

sub find_client {
        my $id = shift;

        foreach my $client ( Slim::Player::Client::clients() ) {
                if ( $client->id() eq $id ) {
                        return $client;
                }
        }
        return undef;
}

sub notification {
        my ($notification) = @_;

        while ( ( $key, $value ) = each %$notification ) {
                $log->debug("key: '$key', value: $hash{$key}\n");
                my $client = find_client($key);
                if ($client) {

                        #			$log->debug( "client is ".$client->name() );

                        my $content = $value;
                        my $dmap    = $$content{"dmap.listingitem"};
                        dmap_lisitingitem_notification( $client, $dmap ) if ($dmap);

                        my $volume = $$content{"volume"};
                        volume_notification( $client, $volume ) if ( defined $volume );

                        my $progress = $$content{"progress"};
                        progress_notification( $client, $progress ) if ( defined $progress );

                }
                else {
                        $log->debug("No client named '$key' yet....");
                }
        }
}

1;
