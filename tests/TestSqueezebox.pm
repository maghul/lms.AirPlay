use strict;

package TestSqueezebox;

use base qw(Test::Class);
use Plugins::AirPlay::Squeezebox;
use Test::More;
use MockClient;

sub test_init : Test(4) {
        my $client     = MockClient::new();
        my $squareplay = Plugins::AirPlay::Squareplay->new();

        my $box = Plugins::AirPlay::Squeezebox->initialize( $client, $squareplay );
        is $box->{name}, "MockClient";
        is $box->{id},   "4711";

        my $box2 = Plugins::AirPlay::Squeezebox->get($client);
        ok defined $box2;
        is $box2, $box;

        $box->close();
}

sub test_volume_notification : Test(4) {
        my $client     = MockClient::new();
        my $squareplay = Plugins::AirPlay::Squareplay->new();

        print "client=$client\n";
        print "client=$client->id()\n";
        my $box = Plugins::AirPlay::Squeezebox->initialize( $client, $squareplay );
        $box->volume_notification(12);
        print "client2=$client\n";
        my $box2 = Plugins::AirPlay::Squeezebox->get($client);
        is $box2, $box;
        is $box->{device_volume},  12, "New Volume";
        is $box2->{device_volume}, 12, "New Volume";
        is_deeply $client->{executed}, [ [ "mixer", "volume", 12 ] ], "Command executed";

        $box->close();
}

1;
