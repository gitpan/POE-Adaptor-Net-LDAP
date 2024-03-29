#!/usr/bin/perl

use strict;
use warnings;

use POE;
use POE::Adaptor::Net::LDAP;

POE::Session->create(
	inline_states => {
		_start => sub {
			my ($heap, $session) = @_[HEAP, SESSION];
			$heap->{ldap} = POE::Adaptor::Net::LDAP->new(
				'localhost',
				callback => $session->postback( 'connect' ),
			);
		},
		connect => sub {
			my ($heap, $session, $callback_args) = @_[HEAP, SESSION, ARG1];
			if ( $callback_args->[0] ) {
				$heap->{ldap}->bind(
					callback => $session->postback( 'bind' ),
				);
			}
			else {
				delete $heap->{ldap};
				print "Connection Failed\n";
			}
		},
		bind => sub {
			my ($heap, $session) = @_[HEAP, SESSION];
			$heap->{ldap}->search(
				base => "ou=People,dc=example,dc=net",
				filter => "(objectClass=person)",
				callback => $session->postback( 'search' ),
			);
		},
		search => sub {
			my ($heap, $ldap_return) = @_[HEAP, ARG1];
			my $ldap_search = shift @$ldap_return;

			foreach (@$ldap_return) {
				print $_->dump;
			}

			delete $heap->{ldap} if $ldap_search->done;
		},
	},
);

POE::Kernel->run();

