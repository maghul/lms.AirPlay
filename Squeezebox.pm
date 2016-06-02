#
#  Controls a squeezebox and server
#

package Plugins::AirPlay::Squeezebox;

use Plugins::AirPlay::Shairplay;

use Data::Dumper;

use Slim::Utils::Log;

my $log = logger('plugin.airplay');

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

sub relative_volume_notification {
        my $client      = shift;
        my $volume      = shift;
        my $prev_volume = shift;

        if ( $volume > 90 ) {
                $log->debug("EMH Relative Mixer volume up!");
                $client->execute( [ "mixer", "volume", "+2" ] );
        }
        elsif ( $volume < 10 ) {
                $log->debug("EMH Relative Mixer volume down!");
                $client->execute( [ "mixer", "volume", "-2" ] );
        }
        else {
                $log->debug("EMH Relative Mixer volume !");
        }

        #	if ( $target_volume ) {
        $target_volume = 50;
        if ( $volume < $target_volume - 3 || $volume > $target_volume + 3 ) {

                #	if ( ! between( $volume,$target_volume,$prev_volume) ) {
                _changeVolume($client);
        }

        #	} else {
        #		setAirPlayDeviceVolume($client, 50);
        #	}
}

sub relativeMixerVolumeCallback {
        my $request = shift;
        my $client  = $request->client;

        setAirPlayDeviceVolume( $client, 50 );
}

sub absolute_volume_notification {
        my $client = shift;
        my $volume = shift;

}

sub volume_notification {
        my $client   = shift;
        my $volume   = shift;
        my $relative = 1;

        my $prev_volume = $sb_volume;
        $sb_volume = airplay_to_squeezebox_volume($volume);

        relative_volume_notification( $client, $sb_volume, $prev_volume );

        #	$log->debug( "Volume=$volume\n" );
        #	$volumeChangePending= 0;
        #
        #	my $new_volume= airplay_to_squeezebox_volume($volume);
        #	$new_volume=0 if ($sb_volume<0);
        #	if ( $relative ) {
        #		if ( $new_volume>90 ) {
        #			$log->debug( "EMH Relative Mixer volume up!" );
        #			$client->execute( [ "mixer", "volume", "+2" ] );
        #		} elsif ( $new_volume<10 ) {
        #			$log->debug( "EMH Relative Mixer volume down!" );
        #			$client->execute( [ "mixer", "volume", "-2" ] );
        #		} else {
        #			$log->debug( "EMH Relative Mixer volume !" );
        #		}
        #	}
        #
        #	if ( defined $target_volume ) {
        #		$log->debug( "EMH new_volume=$new_volume, target_volume=$target_volume, sb_volume=$sb_volume\n" );
        #
        #		if (between( $new_volume, $target_volume, $sb_volume )) {
        #		        $log->debug( "------ Done!\n" );
        #			$sb_volume= $new_volume;
        #			undef $target_volume;
        #		} else {
        #		        $log->debug( "------ Change Volume!\n" );
        #			$sb_volume= $new_volume;
        #			_changeVolume($client);
        #		}
        #	} elsif ( ! $relative ) {
        #		$log->debug( "EMH Absolute Mixer volume $sb_volume!" );
        #		$client->execute( [ "mixer", "volume", $sb_volume ] );
        #	}
}

sub setAirPlayDeviceVolume {
        my $client = shift;
        my $volume = shift;

        my $start = !defined $target_volume;

        $target_volume = $volume;
        $log->debug("EMH setAirPlayDeviceVolume target_volume=$target_volume, start=$start");

        #	if ( $start ) {
        _changeVolume($client);

        #	}
}

sub mixerVolumeCallback {
        my $request  = shift;
        my $client   = $request->client;
        my $relative = 1;

        return if !defined $client;
        relativeMixerVolumeCallback( $request, $client );

        #	return if defined $target_volume;
        #
        #	# TODO: Check if it running airplay.
        #
        #        my $volume= $client->volume();
        #
        #	$log->debug("EMH: mixer volume=$volume");
        #	if ( $relative ) {
        #		setAirPlayDeviceVolume( $client, $center_volume );
        #	} else {
        #		setAirPlayDeviceVolume( $client, $volume+0 );
        #	}
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
