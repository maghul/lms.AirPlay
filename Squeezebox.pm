#
#  Controls a squeezebox and server
#

package Plugins::AirPlay::Squeezebox;

use Plugins::AirPlay::Shairplay;
use Plugins::AirPlay::Squeezeplay;

use Data::Dumper;

use Slim::Utils::Log;

my $log           = logger('plugin.airplay');
my $baseUrl       = Plugins::AirPlay::Squeezeplay::getBaseUrl();
my $center_volume = 52;

sub new {
}

sub initClient {
        my $client = shift;

        $client{airplay} = { name => $client->name() };
}

#sub getinfo {
#	my $client= shift;
#
#	$log->debug("client=".$client);
#	$log->debug("client=".$client->name().", id=".$client->id());
#
#	my $id= $client->id();
#	$$clientinfo{$id} = {} if ( ! exists $$clientinfo{$id} );
#
#	return $$clientinfo{$id};
#}

sub _shutdown_squeezebox {
        $log->warn("Shutting down squeezebox\n");
        my $client = shift;

        #    my $url= shift;

        #    if ( $url eq current-song ) {
        $client->execute( [ "power", "0" ] );

        #    }
}

sub start_player {
        $log->warn("START AirPlay squeezebox\n");
        my $client = shift;

        if ($client) {
                my $client_id = $client->id();
                $log->warn("STARTING AirPlay play\n");
                $client->execute( [ "playlist", "play", "$baseUrl/$client_id/audio.pcm" ] );
        }
        Slim::Utils::Timers::killTimers( $client, \&_shutdown_squeezebox );
}

sub stop_player {
        $log->warn("STOP AirPlay squeezebox\n");
        my $client = shift;
        if ($client) {
                $log->warn("STOPPING AirPlay play\n");
                $client->execute( ["stop"] );
                my $timeout = 20;
                Slim::Utils::Timers::setTimer( $client, Time::HiRes::time() + $timeout, \&_shutdown_squeezebox );
        }
}

sub metaDataProvider {
        my ( $client, $url ) = @_;

        if ( !$client{airplay}->{metadata} ) {
                $client{airplay}->{metadata} = {
                        artist => "",
                        album  => "",

                        bitrate => 44100,
                        type    => "AirPlay"
                };
        }
        print Data::Dump::dump( $client{airplay}->{metadata} );
        return $client{airplay}->{metadata};
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

        $client{airplay}->{metadata} = {
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

sub _volumeCallback {
        $volumeChangePending = 0;
}

sub _changeVolume {
        my $client = shift;

        if ( $client{airplay}->{target_volume} && ( $client{airplay}->{target_volume} != $client{airplay}->{sb_volume} ) ) {

                my $vol = $client{airplay}->{target_volume} < $client{airplay}->{sb_volume} ? "volumedown" : "volumeup";
                $log->debug("changeVolume:EMH: client=$client, target_volume=$client{airplay}->{target_volume}, sb_volume=$client{airplay}->{sb_volume} ==> $vol\n");

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

        my $rv = ( $prev_volume > $volume && $volume <= $client{airplay}->{target_volume} )
          || ( $prev_volume < $volume && $volume >= $client{airplay}->{target_volume} );

        $log->debug("EMH _check_volume_reached target_volume=$client{airplay}->{target_volume}, volume=$volume, prev_volume=$prev_volume --> $rv\n ");

        return $rv;
}

sub setAirPlayDeviceVolume {
        my $client = shift;
        my $volume = shift;

        my $start = !defined $client{airplay}->{target_volume};

        $client{airplay}->{target_volume} = $volume;
        $log->debug("EMH setAirPlayDeviceVolume target_volume=$client{airplay}->{target_volume}, start=$start");
        if ($start) {
                _changeVolume($client);
        }
}

sub _direction_timeout {
        $log->warn("User lifted finger from iPhone\n");
        my $client = shift;
        $client{airplay}->{current_direction} = 0;
}

sub relative_volume_notification {
        my $client      = shift;
        my $volume      = shift;
        my $prev_volume = shift;

        $log->debug("EMH volume=$volume, prev_volume=$prev_volume");
        if ( $volume > $prev_volume && $client{airplay}->{current_direction} >= 0 ) {
                $log->debug("EMH squeezebox volume +2");
                $client->execute( [ "mixer", "volume", "+2" ] );
                $client{airplay}->{current_direction} = 1;
        }
        if ( $volume < $prev_volume && $client{airplay}->{current_direction} <= 0 ) {
                $log->debug("EMH squeezebox volume -2");
                $client->execute( [ "mixer", "volume", "-2" ] );
                $client{airplay}->{current_direction} = -1;
        }

        $client{airplay}->{target_volume} = 50;

        #	if ( $volume<$client{airplay}->{target_volume}-3 || $volume>$client{airplay}->{target_volume}+3 ) {
        $log->debug( "EMH target_volume-3=" . ( $client{airplay}->{target_volume} - 3 ) . ", volume=$volume, target_volume+3=" . ( $client{airplay}->{target_volume} + 3 ) );
        if ( $volume > $client{airplay}->{target_volume} - 3 && $volume < $client{airplay}->{target_volume} + 3 ) {

                #	if (between( $volume, $client{airplay}->{target_volume}, $prev_volume )) {
                undef $client{airplay}->{target_volume};
                Slim::Utils::Timers::setTimer( $client, Time::HiRes::time() + 0.3, \&_direction_timeout );
                $log->debug("EMH Done changing volume");
        }
        else {
                _changeVolume($client);
                Slim::Utils::Timers::killTimers( $client, \&_direction_timeout );
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

        if ( defined $client{airplay}->{target_volume} ) {
                $log->debug("EMH volume=$volume, target_volume=$client{airplay}->{target_volume}, sb_volume=$client{airplay}->{sb_volume}\n");

                if ( between( $volume, $client{airplay}->{target_volume}, $prev_volume ) ) {
                        $log->debug("------ Done!\n");

                        #			$client{airplay}->{sb_volume}= $new_volume;
                        undef $client{airplay}->{target_volume};
                }
                else {
                        $log->debug("------ Change Volume!\n");

                        #			$client{airplay}->{sb_volume}= $new_volume;
                        _changeVolume($client);
                }
        }
        else {
                $log->debug("EMH Absolute Mixer volume $client{airplay}->{sb_volume}!");
                $client->execute( [ "mixer", "volume", $client{airplay}->{sb_volume} ] );
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
        my $client = shift;
        my $volume = shift;

        my $prev_volume = $client{airplay}->{sb_volume};
        $client{airplay}->{sb_volume} = airplay_to_squeezebox_volume($volume);
        $log->debug( "client=" . $client->name() . ", airplay=" . Data::Dump::dump( $client{airplay} ) );

        if ( $client{airplay}->{relative} ) {
                relative_volume_notification( $client, $client{airplay}->{sb_volume}, $prev_volume );
        }
        else {
                absolute_volume_notification( $client, $client{airplay}->{sb_volume}, $prev_volume );
        }

}

sub mixerVolumeCallback {
        my $request = shift;
        my $client  = $request->client;

        return if !defined $client;

        #	$log->debug("getinfo... client=".$client);
        #	my $info= getinfo($client);
        $log->debug( "client=" . $client->name() . ", airplay=" . Data::Dump::dump( $client{airplay} ) );
        if ( $client{airplay}->{relative} ) {
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

                if ( defined $relative ) {
                        $relative = 1;
                        $precise  = 0;
                }
                else {
                        $relative = 0;
                        $precise  = 1;
                }

                #	    $log->debug("getinfo... client=".$client);
                #	    my $info= getinfo($client);
                $client{airplay}->{relative} = $relative;
                $client{airplay}->{precise}  = $precise;
                $log->debug( "client=" . $client->name() . ", id=" . $client->id() . ", relative=$client{airplay}->{relative}, precise=$client{airplay}->{precise}" );

                $log->debug( "client=" . $client->name() . ", airplay=" . Data::Dump::dump( $client{airplay} ) );
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
