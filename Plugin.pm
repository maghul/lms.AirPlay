#
# A plugin to enable ShairPlay to be played using Alsa
#

use strict;

package Plugins::AirPlay::Plugin;

use base qw(Slim::Plugin::OPMLBased);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

use Plugins::AirPlay::Settings;
use Plugins::AirPlay::Shairplay;
use Plugins::AirPlay::CoverArt;
use Plugins::AirPlay::Squeezeplay;

use Data::Dumper;

# create log category before loading other modules
my $log = Slim::Utils::Log->addLogCategory(
        {
                'category'     => 'plugin.airplay',
                'defaultLevel' => 'DEBUG',

                #	'defaultLevel' => 'INFO',
                'description' => getDisplayName(),
        }
);
my $baseUrl = Plugins::AirPlay::Squeezeplay::getBaseUrl();

use Slim::Utils::Misc;
my $prefs = preferences('plugin.airplay');

my $originalPlaylistJumpCommand;

################################
### Plugin Interface ###########
################################

sub initPlugin {
        my $class = shift;

        $log->info( "Initializing AirPlay " . $class->_pluginDataFor('version') );
        Plugins::AirPlay::Settings->new($class);
        Plugins::AirPlay::Settings->init();

        Slim::Web::Pages->addRawFunction( '/airplayimage', \&Plugins::AirPlay::CoverArt::handler );

        # Install callback to get client power state, volume and connect/disconnect changes
        Slim::Control::Request::subscribe( \&clientConnectCallback, [ ['client'] ] );

        Slim::Control::Request::subscribe( \&playCallback,     [ ['pause'] ] );
        Slim::Control::Request::subscribe( \&playCallback,     [ ['play'] ] );
        Slim::Control::Request::subscribe( \&playlistCallback, [ ['playlist'] ] );

        Slim::Control::Request::subscribe( \&timeCallback, [ ['time'] ] );
        Slim::Control::Request::subscribe( \&Plugins::AirPlay::Squeezebox::mixerVolumeCallback, [ [ 'mixer', 'volume' ] ] );

        #   Check volume control type
        Slim::Control::Request::subscribe( \&Plugins::AirPlay::Squeezebox::externalVolumeInfoCallback, [ ['getexternalvolumeinfo'] ] );

        my $baseUrlRe = quotemeta($baseUrl);
        Slim::Formats::RemoteMetadata->registerProvider(
                match => qr/$baseUrlRe/,
                func  => \&Plugins::AirPlay::Squeezebox::metaDataProvider
        );

        # Reroute all playlist jump requests
        $originalPlaylistJumpCommand =
          Slim::Control::Request::addDispatch( [ 'playlist', 'jump', '_index', '_fadein', '_noplay', '_seekdata' ], [ 1, 0, 0, \&playlistJumpCommand ] );

        Plugins::AirPlay::Shairplay::startNotifications();

        Plugins::AirPlay::Squeezeplay::start();

        return 1;
}

sub shutdownPlugin {
        Slim::Control::Request::unsubscribe( \&clientConnectCallback );

        Slim::Control::Request::unsubscribe( \&playCallback );
        Slim::Control::Request::unsubscribe( \&playlistCallback );

        Slim::Control::Request::unsubscribe( \&timeCallback );

        Slim::Control::Request::unsubscribe( \&Plugins::AirPlay::Squeezebox::mixerVolumeCallback );

        Slim::Control::Request::unsubscribe( \&Plugins::AirPlay::Squeezebox::externalVolumeInfoCallback );

        # Remove reroute for all playlist jump requests
        Slim::Control::Request::addDispatch( [ 'playlist', 'jump', '_index', '_fadein', '_noplay', '_seekdata' ], [ 1, 0, 0, $originalPlaylistJumpCommand ] );

        Plugins::AirPlay::Shairplay::stopNotifications();
        return;
}

sub isRunningAirplay {
        my $url       = shift;
        my $baseUrlRe = quotemeta($baseUrl);
        return $url =~ /^$baseUrlRe/;
}

sub playlistJumpCommand {
        my $request  = shift;
        my $client   = $request->client();
        my $index    = $request->getParam('_index');
        my $fadeIn   = $request->getParam('_fadein');
        my $noplay   = $request->getParam('_noplay');
        my $seekdata = $request->getParam('_seekdata');

        my $url = Slim::Player::Playlist::url($client);

        if ( isRunningAirplay($url) ) {
                $log->debug("AIRPLAY command: jump $index");
                Plugins::AirPlay::Shairplay::jump( $client, $index );

                #		Slim::Control::Request::notifyFromArray($client, ['airplay', 'jump', $index],);
                #
                #		if ( $client->isPlaying()) {
                #			return;
                #		}

                # We can't jump anywhere in the playlist but this call does many other things we need done.
                $request->addParam( '_index', 0 );
        }
        eval { &{$originalPlaylistJumpCommand}($request) };
}

sub timeCallback {
        my $request = shift;
        my $client  = $request->client;

        my $stream   = Slim::Player::Playlist::song($client)->path;
        my $playmode = Slim::Player::Source::playmode($client);
        my $mode     = Slim::Buttons::Common::mode($client);

        $log->debug("cli time - playmode=$playmode  stream=$stream ");
        my $time = $request->getParam("_newvalue");
        $log->debug("cli time - time = $time");

        if ( isRunningAirplay($stream) ) {
                Plugins::AirPlay::Shairplay::command( $client, "time/$time" );
        }
}

sub playCallback {
        my $request = shift;
        my $client  = $request->client;

        my $song     = Slim::Player::Playlist::song($client);
        my $stream   = Slim::Player::Playlist::song($client)->path;
        my $playmode = Slim::Player::Source::playmode($client);
        my $mode     = Slim::Buttons::Common::mode($client);
        my $name     = $client->name();

        $log->debug( "duration=" . $song->duration() );
        if ( isRunningAirplay($stream) ) {

                #		if ($prefs->get('pausestop')) {

                #			if ( "play" ne $playmode ) {
                $log->debug("$name: Issuing $playmode");

                #					Plugins::AirPlay::Shairplay::command($client, "playresume");tx

                #					Plugins::AirPlay::Squeezebox::airPlayDevicePlay($client, $playmode eq "play");
                Plugins::AirPlay::Squeezebox::airPlayDevicePlay( $client, 1 ) if ( $playmode eq "play" );
                Plugins::AirPlay::Squeezebox::airPlayDevicePlay( $client, 0 ) if ( $playmode eq "pause" );

                #			}
                #		}
        }

}

sub playlistCallback {
        my $request = shift;
        my $client  = $request->client;

        my $stream = Slim::Player::Playlist::song($client)->path;

        if ( isRunningAirplay($stream) ) {
                if ( $request->isCommand( [ ['playlist'], ['stop'] ] ) ) {
                        $log->debug("CLI Playlist - Playlist stop notification.");
                }
                if ( $request->isCommand( [ ['playlist'], ['index'] ] ) ) {
                        $log->debug("CLI Playlist - Playlist index notification.");
                }
        }
}

# Client connect callback.
sub clientConnectCallback {
        my $request = shift;

        my $client = $request->client();
        return if !defined $client;

        $log->debug( "clientConnectCallback client='" . $client->name() . "'" );

        # Check if new or reconnected client and set current AirPlay state if any.
        if (       $request->isCommand( [ ['client'], ['new'] ] )
                || $request->isCommand( [ ['client'], ['reconnect'] ] ) )
        {
                Plugins::AirPlay::Shairplay::setClientNotificationState($client);

                # TODO: Only call this once
                #				Plugins::AirPlay::Shairplay::startSession( $client );
                Plugins::AirPlay::Squeezebox::initClient($client);

                $log->debug("Trying to get external volume info for new player...");
                Slim::Control::Request::executeRequest( $client, ['getexternalvolumeinfo'] );

        }
        if ( $request->isCommand( [ ['client'], ['disconnect'] ] ) ) {

                # TODO: Only call this once
                Plugins::AirPlay::Shairplay::stopSession($client);
                Plugins::AirPlay::Squeezebox::initClient($client);
        }
}

sub getDisplayName() {
        return ('PLUGIN_AIRPLAY');
}

1;

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
