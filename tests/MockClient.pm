use strict;

package MockClient;

sub new {
        my $mockClient = { executed => [] };

        bless $mockClient;

        return $mockClient;
}

sub id {
        my $self = shift;

        return 4711;
}

sub name {
        my $self = shift;

        return "MockClient";
}

sub execute {
        my $self = shift;
        my $cmd  = shift;

        push $self->{executed}, $cmd;
}

1;
