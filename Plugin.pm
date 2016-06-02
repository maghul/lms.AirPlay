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

use Slim::Utils::Misc;
my $prefs = preferences('plugin.airplay');

my $originalPlaylistJumpCommand;

################################
### Plugin Interface ###########
################################

sub initPlugin {
        my $class = shift;

        $log->info("Initialising AirPlay ");
        $log->info( "Initialising AirPlay " . $class->_pluginDataFor('version') );
        Plugins::AirPlay::Settings->new($class);
        Plugins::AirPlay::Settings->init();
        Plugins::AirPlay::HTTP->init();    # TODO: Remove... maybe?

        #	Slim::Control::Request::subscribe( \&pauseCallback, [['pause']] );
        Slim::Control::Request::subscribe( \&playlistCallback, [ ['playlist'] ] );

        # Reroute all playlist jump requests
        $originalPlaylistJumpCommand =
          Slim::Control::Request::addDispatch( [ 'playlist', 'jump', '_index', '_fadein', '_noplay', '_seekdata' ], [ 1, 0, 0, \&playlistJumpCommand ] );

        # This actually does nothing. It is used for notifications to the AirPlay server
        Slim::Control::Request::addDispatch( [ 'airplay', '_command', '_arg1' ], [ 1, 0, 0, undef ] );

        Plugins::AirPlay::Shairplay->startNotifications();

        return 1;
}

sub playlistJumpCommand {
        my $request  = shift;
        my $client   = $request->client();
        my $index    = $request->getParam('_index');
        my $fadeIn   = $request->getParam('_fadein');
        my $noplay   = $request->getParam('_noplay');
        my $seekdata = $request->getParam('_seekdata');

        my $url = Slim::Player::Playlist::url($client);

        if ( $url =~ /^airplay:/ ) {
                $log->debug("AIRPLAY command: jump $index");
                Slim::Control::Request::notifyFromArray( $client, [ 'airplay', 'jump', $index ], );

                if ( $client->isPlaying() ) {
                        return;
                }

                # We can't jump anywhere in the playlist but this call does many other things we need done.
                $request->addParam( '_index', 0 );
        }
        eval { &{$originalPlaylistJumpCommand}($request) };
}

sub pauseCallback {
        my $request = shift;
        my $client  = $request->client;

        my $stream   = Slim::Player::Playlist::song($client)->path;
        my $playmode = Slim::Player::Source::playmode($client);
        my $mode     = Slim::Buttons::Common::mode($client);

        $log->debug("cli Pause - playmode=$playmode  stream=$stream ");

        if ( $stream =~ /^airplay:/ ) {

                #	if ($playmode eq 'pause' && $stream =~ /^airplay:/ ) {
                if ( $prefs->get('pausestop') ) {
                        $log->debug("Issuing stop");
                        $client->execute( ['stop'] );
                }
        }

}

sub playlistCallback {
        my $request = shift;
        my $client  = $request->client;

        #	my $stream  = Slim::Player::Playlist::song($client)->path;

        $log->debug( "CLI Playlist - request=$request, client=$client " . Dumper($request) );

        if ( $request->isCommand( [ ['playlist'], ['stop'] ] ) ) {
                $log->debug("CLI Playlist - Playlist stop notification.");
                Slim::Control::Request::notifyFromArray( $client, [ 'airplay', 'stop' ], );
        }
}

sub shutdownPlugin {

        #	Slim::Control::Request::unsubscribe(\&pauseCallback);
        return;
}

sub getDisplayName() {
        return ('PLUGIN_AIRPLAY');
}

1;

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
