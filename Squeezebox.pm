#
#  Controls a squeezebox and server
#

package Plugins::AirPlay::Squeezebox;

use Plugins::AirPlay::Squareplay;

use Data::Dumper;
use Encode qw( decode encode );

use Scalar::Util qw(blessed);
use Slim::Control::Request;
use Slim::Utils::Log;

use overload 
    '""' => 'stringify';

my $log           = logger('plugin.airplay');
my $center_volume = 52;

my $airplay = {};

sub getOrCreate {
        my $class      = shift;
        my $client     = shift;
        my $squareplay = shift;

	my $id = $client->id();
	
        my $self = $$airplay{$id};
	return $self if defined $self;
	
        my $self = {
                client     => $client,
                name       => $client->name(),    # TODO: Remove
                id         => $client->id(),      # TODO: Remove
                squareplay => $squareplay,
                relative   => 0,
                precise    => 1,
		source     => "",
        };

        $br = bless( $self, $class );

	$log->debug("New client '$id'");
	$$airplay{$id} = $br;

        return $br;
}

sub sendStart {
        my $self = shift;

	my $squareplay = $self->{squareplay};
	
	$log->debug("Trying to get external volume info for new player...");
	$squareplay->post_request( "control/start", $self->getJsonString(),
				   sub {
					   $self->sendVolumeMode();
					   
				   }, 
				   sub {
					   $log->debug( "control/start error callback : ".$self);
					   
				   } );
}


sub close {
        my $self = shift;

        my $id = $self->id();
        if ( defined $$airplay{$id} ) {
                delete $$airplay{$id};

                my $squareplay = $self->{squareplay};
                $squareplay->post_request( "control/stop", $self->getJsonString() );
        }
}

sub stringify {
        my $self = shift;
	my $name = $self->name();
	my $id = $self->id();
	return sprintf "Squeezebox{'%s','%s',connected to '%s'}", $name, $id, $self->{source};
}


sub getById {
        my $id = shift;

        my $br = $$airplay{$id};
	if (! defined $br) {
		$log->error( "Client ID=$id has no assigned box" );
	}
        return $br;
}

sub get {
        my $class  = shift;
        my $client = shift;

        my $id = $client->id();
	return getById($id);
}

sub uri {
        my $self    = shift;
        my $request = shift;

        my $squareplay = $self->{squareplay};

        my $uri = $squareplay->uri( $self->id() . "/$request" );
        return $uri;
}

sub name {
        my $self = shift;
        return $self->{name};
}

sub id {
        my $self = shift;
        return $self->{id};
}

sub execute {

        # Execute a command on the squeezebox server
        my $self = shift;
        my $cmd  = shift;

        my $client = $self->{client};
        $client->execute($cmd);
}

sub command {

        # Send a DACP command to the AirPlay source
        my $self     = shift;
        my $command  = shift;
        my $callback = shift;

        my $squareplay = $self->{squareplay};

        $log->info( $self->name() . ": command '$command'" );
        my $uri = $self->uri("control/$command");
        $squareplay->_tx( $uri, $callback );
}

sub jump {
        my $self  = shift;
        my $index = shift;
        if ( $index != 0 ) {
                $self->command("pause");
                $self->command( $index > 0 ? "nextitem" : "previtem" );
                $self->command("playresume");
        }
}

sub seek {
        my $self = shift;
        my $time = shift;

        $self->command("time/$time");
}

sub _shutdown_squeezebox {
        # poweroff the squeezebox.
        my $self = shift;
	my $name = $self->name();
	
        $log->debug("$name: Shutting down squeezebox\n");
        $self->execute( [ "power", "0" ] );
}

sub start_player {
        # Start playing a track from the Squareplay server.
        my $self = shift;
	my $name = $self->name();

        $log->debug("$name: running playlist play\n");
        $self->execute( [ "playlist", "play", $self->uri("audio.pcm") ] );
        Slim::Utils::Timers::killTimers( $self, \&_shutdown_squeezebox );
}

sub stop_player {
        # Stop the player.
        my $self = shift;
	my $name = $self->name();

        $log->debug("$name: running AirPlay stop\n");
        $self->execute( ["stop"] );
        my $timeout = 20;
        Slim::Utils::Timers::setTimer( $self, Time::HiRes::time() + $timeout, \&_shutdown_squeezebox );
}

# TODO: class method
sub metaDataProvider {
        my ( $client, $url ) = @_;

        $self = Plugins::AirPlay::Squeezebox->get($client);
        return $self->metaData() if defined $self;
}

sub metaData {

        # Get the metadata for the current track playing
        my ( $self, $url ) = @_;

        if ( !$self->{metadata} ) {
                $self->{metadata} = {
                        artist => "",
                        album  => "",

                        bitrate => 44100,
                        type    => "AirPlay"
                };
        }
        return $self->{metadata};
}

sub dmap_notification {
        my $self = shift;
        my $dmap = shift;

	my $itemid = $$dmap{'dmap.persistentid'};
	
        $self->{metadata} = {
		title  => $$dmap{'dmap.itemname'},
                artist => $$dmap{'daap.songartist'},
                album  => $$dmap{'daap.songalbum'},

                cover => $self->uri("cover.jpg?$itemid"),
                tracknum => $$dmap{'daap.songtracknumber'},
                duration => $$dmap{'daap.songtime'}/1000,
                bitrate  => 44100,
                type     => "AirPlay ".$self->{source}
		    
        };

        my $trackurl = $self->uri("audio.pcm");
        Slim::Music::Info::setRemoteMetadata( $trackurl, { title => $$dmap{'dmap.itemname'}, } );

        my $itemid = $$dmap{'dmap.persistentid'};
        my $obj    = Slim::Schema::RemoteTrack->updateOrCreate( $trackurl, $self->{metadata} );
}

sub progress_notification {
        my $self     = shift;
        my $progress = shift;

        my $client = $self->{client};
	my $song   = $client->streamingSong;

##	start_player($client); # Might flush?
	if (defined $song) {
		my $newtime = $$progress{current} / 1000;
		my $length  = $$progress{length} / 1000;

		$song->startOffset( $newtime - $client->songElapsedSeconds() );
		$song->duration($length);
		if ( $log->is_debug ) {
			my $client = $self->{client};
			my $name   = $client->name();
			$log->debug( "$name: song=" . $song->duration );
		}
	}
}

sub setAirPlayDeviceVolume {
        my $self   = shift;
        my $volume = shift;

        if ( !$self->{relative} ) {
                $self->command("volume/$volume");
        }
}

sub airPlayDevicePlay {
        my $self = shift;
        my $play = shift;

        my $name        = $self->name();
        my $playerstate = $self->{playerstate};
        my $newstate    = $play ? "playresume" : "pause";

        $log->debug("$name: Current Playerstate=$playerstate, New State=$newstate\n");
        if ( $playerstate ne $newstate ) {
                $self->command($newstate);
                $self->{playerstate} = $newstate;
        }
}

sub source_notification {
        my $self   = shift;
        my $source = shift;

	$source =~ s/\..*//;

        $self->{source} = $source;
	$self->{metadata}->{type} = "AirPlay ".$self->{source}
}

sub volume_notification {
        my $self   = shift;
        my $volume = shift;

        $self->{device_volume} = $volume;
        my $client = $self->{client};
        $client->execute( [ "mixer", "volume", $volume ] );
}

sub mixerVolumeQueryCallback {

        # Not a method
        my $request = shift;
        my $client  = $request->client;

        my $volume = $request->getResult("_volume");
        my $name   = $client->name();
        my $box    = Plugins::AirPlay::Squeezebox->get($client);

        if ( !$box->{relative} ) {
                $log->debug( "$name: request volume=$volume, box=$box, device volume=" . $box->{device_volume} );
                if ( $volume != $box->{device_volume} ) {
                        $box->setAirPlayDeviceVolume( $volume + 0 );
                }
        }
        else {
                $log->debug("$name: request volume, device is using relative volume, not sending any data");
        }
}

sub mixerVolumeCallback {

        # Not a method
        my $request = shift;
        my $client  = $request->client;

        return if !defined $client;

        my $box = Plugins::AirPlay::Squeezebox->get($client);
        if ( !$box->{relative} ) {

                # The volume sent as argument may not be the correct one as it can be the
                # fixed volume intended for the squeezebox. Ask for the real one instead
                # and send that to the device.
		my $request = Slim::Control::Request->new( $client->id(), [ 'mixer', 'volume', '?' ], 1 );
		$request->callbackParameters( \&mixerVolumeQueryCallback );
		$request->execute();
        }
}

# Get the parameter key:value pair and update the key in self
# if it has changed. Returns "true" if there was a change.
sub _setExternalVolumeInfo {
        my ( $self, $param ) = @_;

        if ( $param =~ /([a-z]*):([01])/ ) {
                if ( $self->{$1} != $2 ) {
                        $self->{$1} = $2;
                        return 1;
                }
        }
        return 0;
}

sub sendVolumeMode {
	my $self= shift;
	
	if ( $self->{precise} ) {
		$self->command("volume/absolute");
	} else {
		$self->command("volume/relative");
	}
}

sub checkVolumeInfoCallback {
	my $self= shift;
        my $request = shift;
	
	my $name = $self->name();
	
	my $change = 0;
	$change |= $self->_setExternalVolumeInfo( $request->getParam('_p1') );
	$change |= $self->_setExternalVolumeInfo( $request->getParam('_p2') );
	
	if ( $change ) {
		$log->debug( "$name: volume info changed, relative=".$self->{relative}.", precise=".$self->{precise} );
		$self->sendVolumeMode();
	}
}


# Execute a externalvolumeinfo request for the squeezebox
sub getexternalvolumeinfo {
        # Not a method
	my ( $box )  = @_;
        my $id = (blessed($box))?$box->{id}:undef;
	#	Slim::Control::Request::executeRequest( $client, ['getexternalvolumeinfo'] );
	
	my $request = Slim::Control::Request->new( 
		$id,
		['getexternalvolumeinfo'],
		1
	);

	$request->execute();
}

# TODO: We should get the callback when prefs are changed but that doesn't seem to happen...
sub externalVolumeInfoCallback {
        # Not a method
        my $request = shift;
        $client = $request->client;

        if ($client) {
                my $box  = Plugins::AirPlay::Squeezebox->get($client);
		$box->checkVolumeInfoCallback($request);
        }
}

sub send_volume_control_state {
        $self = shift;
        $log->debug( $self->name() . ": id=" . $self->id() );
        if ( defined $self->{relative} ) {
                $self->command("volume/relative");
        }
}

sub isRunningAirplay {
        my $self   = shift;
        my $client = $self->{client};
        my $url    = Slim::Player::Playlist::url($client);
        return Plugins::AirPlay::Plugin::isRunningAirplay($url);
}

sub notification {

        # Not a method
        my ($notification) = @_;

        while ( ( $key, $value ) = each %$notification ) {
                $log->debug( "key: '$key', value: " . Data::Dump::dump($value) );
                my $box = getById($key);
                if ( $box ) {
			if ( $box->isRunningAirplay() ) {
				my $content = $value;
				my $dmap    = $$content{"dmap.listingitem"};
				$box->dmap_notification($dmap) if ($dmap);
				
				my $source = $$content{"source"};
				$box->source_notification($source) if ( defined $source );
				
				my $volume = $$content{"volume"};
				$box->volume_notification($volume) if ( defined $volume );
				
				my $progress = $$content{"progress"};
				$box->progress_notification($progress) if ( defined $progress );
			}
			
			$box->start_player() if ( $value eq "play" );
			$box->stop_player()  if ( $value eq "pause" );
			$box->stop_player()  if ( $value eq "stop" );
                }
                else {
                        $log->debug("No client named '$key' yet....");
                }
        }
}

sub getJsonString {
        my $self = shift;

        my $client = $self->{client};

        my $id   = $client->id();
        my $name = $client->name();

        my $json = "[{\"id\":\"$id\",\"name\":\"$name\"}]";
	$json = encode( 'utf-8', $json );
	return $json;
}

}

1;
