#!/usr/bin/perl

$| = 1;

use strict;
use warnings;

use lib 'lib';
use POE qw(Adaptor::Net::LDAP);

POE::Session->create(
  inline_states => {
    _start => sub {
      print "Start\n";
      my $ldap = $_[HEAP]->{foo} = POE::Adaptor::Net::LDAP->new( 'localhost' );
      print "LDAP: $ldap\n";
      $ldap->bind( callback => $_[SESSION]->postback( 'bound' ) );
    },
    _stop => sub {
      print "Stop\n";
    },
    bound => sub {
      print "Bound! $_[ARG1]->[0]\n";
      $_[HEAP]->{foo}->search(
        base => "ou=People,dc=domain,dc=net",
        filter => "(objectClass=person)",
        callback => $_[SESSION]->postback( 'search' )
      );
    },
    search => sub {
      print "Got Search result: @{$_[ARG1]}\n";
      if (exists( $_[ARG1]->[1] ) && $_[ARG1]->[1]->can( 'dump' )) {
        print $_[ARG1]->[1]->dump();
      }
      elsif (@{$_[ARG1]} == 1) {
        delete $_[HEAP]->{foo};
      }
    },
  },
);

print "Before run()\n";

POE::Kernel->run();

print "After run()\n";
