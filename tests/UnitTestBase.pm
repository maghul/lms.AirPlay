#use strict;

use Devel::StackTrace;

use constant SLIM_SERVICE => 0;
use constant SCANNER      => 0;
use constant ISWINDOWS    => 0;
use constant PERFMON      => 0;
use constant DEBUGLOG     => 0;
use constant INFOLOG      => 0;

package main;
use constant RESIZER => 0;
use constant WEBUI   => 0;

use constant VIDEO         => 0;
use constant MEDIASUPPORT  => 0;
use constant IMAGE         => 0;
use constant ISMAC         => 0;
use constant LOCALFILE     => 0;
use constant STATISTICS    => 0;
use constant TRANSCODING   => 0;
use constant SB1SLIMP3SYNC => 0;
use constant HAS_AIO       => 0;

#use constant  => 0;
#use constant  => 0;
#use constant  => 0;
#use constant  => 0;
#use constant  => 0;

BEGIN {
        my ( $package, $filename, $line, $subroutine, $hasargs, $wantarray, $evaltext, $is_require, $hints, $bitmask, $hinthash ) = caller(2);
        push @ARGV, "d_startup";
        require Exporter;

        #	$Exporter::Verbose = 1;

        print "Running $filename\n";

        my $dir = `pwd`;
        chomp $dir;
        $dir =~ s#/Plugins/.*##;
        push @INC, $dir;

        use Slim::bootstrap;
        Slim::bootstrap->loadModules( "", "", "/usr/share/squeezeboxserver" );

}

use Slim::Music::TitleFormatter;
use Data::Dumper;
use XML::Simple;
use Slim::Utils::Log;

my $filename;
my $testname;

sub getDisplayName {
        return 'TestChannelParser';
}

sub params {
        return { url => 'testurl' };
}

sub contentRef {

        #    my $filename="channels.aspx";
        open my $fh, '<', $filename or die "error opening $filename: $!";
        my $data = do { local $/; <$fh> };
        return $data;
}

#Slim::Utils::Log->init({logdir => '/tmp', debug => "plugin.srplay"});
Slim::Utils::Log->init( { logdir => '/tmp' } );
my $log = Slim::Utils::Log->addLogCategory(
        {
                'category'     => 'plugin.srplay.parser',
                'defaultLevel' => 'ERROR',
                'description'  => getDisplayName(),
        }
);

sub getHttp {
        my ($file) = @_;
        $filename = $file;
        my $http = {};

        bless $http;

        return $http;
}

1;
