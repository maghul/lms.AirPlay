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

my $airplay = {};

sub new {
}

sub initClient {
        my $client = shift;

        if ( !exists $$airplay{ $client->id() } ) {
                $$airplay{ $client->id() } = { name => $client->name() };
        }
}

sub airplay {
        my $client = shift;

        return $$airplay{ $client->id() };
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
        my $client = shift;

        #    my $url= shift;

        #    if ( $url eq current-song ) {
        $log->debug("$name: Shutting down squeezebox\n");
        $client->execute( [ "power", "0" ] );

        #    }
}

sub start_player {
        my $client = shift;

        if ($client) {
                my $client_id = $client->id();
                my $name      = $client->name();
                $log->debug("$name: running playlist play\n");
                $client->execute( [ "playlist", "play", "$baseUrl/$client_id/audio.pcm" ] );
        }
        Slim::Utils::Timers::killTimers( $client, \&_shutdown_squeezebox );
}

sub stop_player {
        my $client = shift;
        if ($client) {
                my $name = $client->name();
                $log->debug("$name: running AirPlay stop\n");
                $client->execute( ["stop"] );
                my $timeout = 20;
                Slim::Utils::Timers::setTimer( $client, Time::HiRes::time() + $timeout, \&_shutdown_squeezebox );
        }
}

sub metaDataProvider {
        my ( $client, $url ) = @_;

        if ( !$$airplay{ $client->id() }->{metadata} ) {
                $$airplay{ $client->id() }->{metadata} = {
                        artist => "",
                        album  => "",

                        bitrate => 44100,
                        type    => "AirPlay"
                };
        }
        return $$airplay{ $client->id() }->{metadata};
}

sub dmap_lisitingitem_notification {
        my $client = shift;
        my $dmap   = shift;

        my $id       = $client->id();
        my $name     = $client->name();
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

        $$airplay{ $client->id() }->{metadata} = {
                artist => $$dmap{'daap.songartist'},
                album  => $$dmap{'daap.songalbum'},

                coverurl => "airplayimage/$id/cover.$itemid.jpg",
                tracknum => $$dmap{'daap.songtracknumber'},
                bitrate  => 44100,
                type     => "AirPlay"
        };

}

sub progress_notification {
        my $client   = shift;
        my $progress = shift;

        my $name    = $client->name();
        my $song    = $client->streamingSong;
        my $newtime = $$progress{current} / 1000;
        my $length  = $$progress{length} / 1000;

        #	start_player($client); # Might flush?
        $song->startOffset( $newtime - $client->songElapsedSeconds() );
        $song->duration($length);
        $log->debug( "$name: song=" . $song->duration );

}

sub setAirPlayDeviceVolume {
        my $client = shift;
        my $volume = shift;

        Plugins::AirPlay::Shairplay::command( $client, "volume/$volume" );
}

sub airPlayDevicePlay {
        my $client  = shift;
        my $play    = shift;
        my $airplay = $$airplay{ $client->id() };
        my $name    = $client->name();

        my $playerstate = $airplay->{playerstate};
        my $newstate = $play ? "playresume" : "pause";

        $log->debug("$name: Current Playerstate=$playerstate, New State=$newstate\n");
        if ( $playerstate ne $newstate ) {
                Plugins::AirPlay::Shairplay::command( $client, $newstate );
                $airplay->{playerstate} = $newstate;
        }
}

sub volume_notification {
        my $client = shift;
        my $volume = shift;

        my $d = airplay($client);
        $d->{device_volume} = $volume;

        $client->execute( [ "mixer", "volume", $volume ] );

}

sub mixerVolumeQueryCallback {
        my $request = shift;
        my $client  = $request->client;

        my $volume = $request->getResult("_volume");
        my $name   = $client->name();
        my $dev    = $$airplay{ $client->id() };
        if ( !$dev->{relative} || ( $dev->{precise} ) ) {
                $log->debug( "$name: request volume=$volume, device volume=" . $d->{device_volume} );
                if ( $volume != $d->{device_volume} ) {
                        setAirPlayDeviceVolume( $client, $volume + 0 );
                }
        }
        else {
                $log->debug("$name: request volume, device is using relative volume, not sending any data");
        }
}

sub mixerVolumeCallback {
        my $request = shift;
        my $client  = $request->client;

        return if !defined $client;

        my $dev = $$airplay{ $client->id() };
        if ( !$dev->{relative} || ( $dev->{precise} ) ) {

                # The volume sent as argument may not be the correct one as it can be the
                # fixed volume intended for the squeezebox. Ask for the real one instead
                # and send that to the device.
		my $request = Slim::Control::Request->new( $client->id(), [ 'mixer', 'volume', '?' ], 1 );
		$request->callbackParameters( \&mixerVolumeQueryCallback );
		$request->execute();
        }
}

sub _setExternalVolumeInfo {
        my ( $dev, $param ) = @_;

        if ( $param =~ /([a-z]*):([01])/ ) {
                if ( $dev->{$1} != $2 ) {
                        $dev->{$1} = $2;
                        return 1;
                }
        }
        return 0;
}

# TODO: We should get the callback when prefs are changed but that doesn't seem to happen...
sub externalVolumeInfoCallback {
        my $request = shift;
        $client = $request->client;

        if ($client) {
                my $dev  = $$airplay{ $client->id() };
                my $name = $client->name();

                my $change = 0;
                $change |= _setExternalVolumeInfo( $dev, $request->getParam('_p1') );
                $change |= _setExternalVolumeInfo( $dev, $request->getParam('_p2') );

                if ( $change && $dev->{relative} && !( $dev->{precise} ) ) {
                        $log->debug( "$name: volume info changed " . Data::Dump::dump($dev) );
                        setAirPlayDeviceVolume( $client, "relative" );
                }
        }
}

sub send_volume_control_state {
        $client = shift;
        $log->debug( $client->name() . ": id=" . $client->id() . ", relative=$$airplay{$client->id()}->{relative}, precise=$$airplay{$client->id()}->{precise}" );
        if ( defined $$airplay{ $client->id() }->{relative} ) {
                setAirPlayDeviceVolume( $client, "relative" );
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
                $log->debug( "key: '$key', value: " . Data::Dump::dump($value) );
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
