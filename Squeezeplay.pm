#
#  Manage the squeezeplay daemon.
#
package Plugins::AirPlay::Squeezeplay;

use strict;

use Slim::Utils::Log;
use Slim::Utils::Network;

use Proc::Background;
use File::ReadBackwards;
use File::Spec::Functions;
use JSON::XS::VersionOneAndTwo;
use Config;

my $squeezeplay;
my $log = logger('plugin.airplay');

sub logFile {
        return catdir( Slim::Utils::OSDetect::dirsFor('log'), "squeezeplay.log" );
}

sub start {
        my $helper = "squeezeplay";
        my $keyPath = Slim::Utils::Misc::findbin("airport.key") || do {
                $log->debug("helper app: airport.key not found");
                return;
        };
        my $helperName = Slim::Utils::Misc::findbin($helper) || do {
                $log->debug("helper app: $helper not found");

                #//	if (! --$count) {
                #//	    $log->error("no spotifyd helper found");
                #//	}
                #//	$try->();
                return;
        };
        my $helperPath = Slim::Utils::OSDetect::getOS->decodeExternalHelperPath($helperName);
        my $logfile    = logFile();

        $log->info("starting $helperPath -k $keyPath -l $logfile");

        $squeezeplay = undef;
        eval { $squeezeplay = Proc::Background->new( { 'die_upon_destroy' => 1 }, $helperPath, "-k", $keyPath, "-l", $logfile ); };

}

my $baseurl;

sub getBaseUrl() {
        if ( !defined $baseurl ) {
                my $hostname = Slim::Utils::Network::hostAddr();
                $baseurl = "http://$hostname:6111";
        }
        return $baseurl;
}

1;
