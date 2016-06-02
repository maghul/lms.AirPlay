use strict;

use base qw(Test::Class);
use Test::More;
use Plugins::AirPlay::Squeezebox;
use MockClient;

sub test_volume_notification : Test(2) {
        my $client = MockClient::new();
        Plugins::AirPlay::Squeezebox::initClient($client);
        Plugins::AirPlay::Squeezebox::volume_notification( $client, 12 );
        my $airplay = Plugins::AirPlay::Squeezebox::airplay($client);
        is $airplay->{device_volume}, 12, "New Volume";
        is_deeply $client->{executed}, [ [ "mixer", "volume", 12 ] ], "Command executed";
}

1;
