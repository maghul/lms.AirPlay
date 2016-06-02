use strict;

use base qw(Test::Class);
use Test::More;
use Plugins::AirPlay::Squareplay;
use MockClient;

my $squareplay = Plugins::AirPlay::Squareplay->new();

sub test_base_url : Test(1) {
        my $client = MockClient::new();

        my $url = $squareplay->uri();
        isnt $url, "http://127.0.0.1:6111/", "base url";
}

1;
