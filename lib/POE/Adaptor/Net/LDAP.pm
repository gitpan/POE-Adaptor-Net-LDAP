package POE::Adaptor::Net::LDAP;

=head1 NAME

POE::Adaptor::Net::LDAP - POE Adaptor for using Net::LDAP in an async environment.

=head1 USE

See the included sample script for a usage start. The API for this module is considered
unstable at this point, however this is working at this time.

=head1 BUGS

What?

=head1 AUTHOR

Jonathan Steinert
hachi@cpan.org

=head1 LICENSE

Copyright 2004 Jonathan Steinert (hachi@cpan.org)

This program is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.

=cut

use base 'Net::LDAP';

use 5.006;
use Net::LDAP::ASN qw(LDAPResponse);
use POE qw(Filter::Stream Filter::ASN1 Wheel::ReadWrite Driver::SysRW);
use WeakRef;

use strict;
use warnings;

our $VERSION = '0.01';

my $poe_session;
my $poe_states = {
  _start => sub {
    $poe_session = $_[SESSION];
  },
  _stop => sub {
    $poe_session = undef;
  },
  new_ldap => sub {
    my $ldap_object = $_[ARG0];

    # For each POEY-Net::LDAP object started, make sure the singleton
    # session handling the I/O stays alive.
    $_[KERNEL]->refcount_increment( $_[SESSION]->ID(), 'POE-LDAP' );

    my $wheel = POE::Wheel::ReadWrite->new(
      Handle => $ldap_object->socket(),
      Driver => POE::Driver::SysRW->new(),
      InputFilter => POE::Filter::ASN1->new(),
      OutputFilter => POE::Filter::Stream->new(),
      InputEvent => 'got_input',
      FlushedEvent => 'flushed_output', # TODO: handle this
      ErrorEvent => 'wheel_error', # TODO: handle this
    );

    # Store the wheel away for safekeeping later when we get a packet back.
    $ldap_object->poe_wheel($wheel);

    # Weaken the $ldap_object as stored in the session heap, this makes
    # the POEY-Net::LDAP object destruct as expected.
    weaken($_[HEAP]->{wheels}->{$wheel->ID()} = $ldap_object);
  },
  remove_ldap => sub {
    my $ldap_object = $_[ARG0];

    my $wheel = $ldap_object->poe_wheel() || '';

    # If this object has no POE wheel in it, we don't really want to clean up.
    if ( $wheel ) {
      $_[KERNEL]->refcount_decrement( $_[SESSION]->ID(), 'POE-LDAP' );
      delete $_[HEAP]->{wheels}->{$wheel->ID()};
      $ldap_object->poe_wheel('');
    }
  },
  got_input => sub {
    my $result = $LDAPResponse->decode($_[ARG0]);

    my $mid = $result->{messageID};
    my $mesg = $_[HEAP]->{wheels}->{$_[ARG1]}->{net_ldap_mesg}->{$mid};

    unless ($mesg) {
      if (my $ext = $result->{protocolOp}{extendedResp}) {
        if (($ext->{responseName} || '') eq '1.3.6.1.4.1.1466.20036') {
	    # TODO: handle this
 	    die("Notice of Disconnection");
        }
      }

      # TODO: handle this
      # print "Unexpected PDU, ignored\n";
      return;
    }
    
    $mesg->decode($result);
  },
};

# POE Wheel accessor for the POEY-Net::LDAP object.
sub poe_wheel {
  my $self = shift;
  
  # Because Net::LDAP objects seem to clone at times, I have to use a stringy
  # version of the object as part of the key. I haven't looked for where the clone
  # happens yet, so this is a hack that could possibly race. However it works for now
  # so I'm going to leave it till a better solution presents itself.

  if (@_) {
    $self->{$self . '_poe_wheel'} = $_[0];
  }

  if (exists( $self->{$self . '_poe_wheel'} )) {
    return $self->{$self . '_poe_wheel'};
  }

  return undef;
}

sub new {
  my $class = shift;

  my $net_ldap = $class->SUPER::new(@_, async => 1);

  POE::Session->create(
    inline_states => $poe_states,
  );

  POE::Kernel->call( $poe_session, 'new_ldap', $net_ldap );
  
  return $net_ldap;
}

sub DESTROY {
  my $self = shift;
  
  POE::Kernel->call( $poe_session, 'remove_ldap', $self );

  $self->SUPER::DESTROY(@_);
}

# Send messages via the POE Wheel system, so that output buffering can happen.
sub _sendmesg {
  my $self = shift;
  my $mesg = shift;

  $self->poe_wheel()->put( $mesg->pdu );

  my $mid = $mesg->mesg_id;

  $self->{net_ldap_mesg}->{$mid} = $mesg;
}
