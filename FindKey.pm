#!/bin/perl -w
package Plugins::AirPlay::FindKey;

use strict;
use LWP::UserAgent;
use HTTP::Request;
use Digest::MD5 qw(md5_base64);

use Slim::Utils::Log;

my $log = logger('plugin.airplay');

sub ok {
	my $hash= shift;

	return $hash eq 'Q706CXq2SsbPFfzyjB22FQ';
}

sub load {
	my $ua= shift;
	my $url= shift;
	my $keyfile= shift;
	
	print "URL=$url\n";

	my $req = HTTP::Request->new(GET => $url);
	my $res = $ua->request($req);
	
	if ($res->is_success) {
		my $key= $res->content;
		if ($key =~ /-----BEGIN RSA PRIVATE KEY-----/) {
			
			$key =~ s/.*-----BEGIN RSA PRIVATE KEY-----//s;
			$key =~ s/-----END RSA PRIVATE KEY-----.*//s;

			
			$key =~ s/<[^<]*>//g;
			$key =~ s/&[^;]*;//g;
			$key =~ s/\s*//;
			$key =~ s/\\.//;
			$key =~ s/\\//;
			$key =~ s/\s//g;
			$key =~ s/(.{1,76})/$1\n/gs;
			$key = "-----BEGIN RSA PRIVATE KEY-----\n$key-----END RSA PRIVATE KEY-----\n";
			$log->error( "Got Key: $key\n" );
			if (ok(md5_base64($key))) {
				$log->error( "Saving key to $keyfile\n" );
				$log->error( "KEY='$key'\n" );
				open OUTPUT, "> $keyfile";
				print OUTPUT $key;
				close OUTPUT;
				return 1;
			}
		}
	} else {
		print $res->status_line, "\n";
	}
	return 0;
}


sub search {
	my $keyfile= shift;
	
	my $ua = LWP::UserAgent->new;
	$ua->agent("Squareplay/0.1 ");
	
	my  $url='https://duckduckgo.com/html/?q=MIIEpQIBAAKCAQEA59dE8';
	my $req = HTTP::Request->new(GET => $url);
	my $res = $ua->request($req);
	
	if ($res->is_success) {
		my $line;
		for $line  ( split(/\n/, $res->content) ) {
			if ( $line =~ /result__snippet/ ) {
				my $url= $line;
				
				$url =~ s/.*href=\"http/http/;
				$url =~ s/\">.*//;
				$log->error( "Checking URL: $url\n" );
				if (load( $ua, $url, $keyfile )) {
					return 1;
				}
			}
		}
	} else {
		print $res->status_line, "\n";
		return 0;
	}
}

1;

