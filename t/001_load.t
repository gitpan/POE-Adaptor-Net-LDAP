# -*- perl -*-

# t/001_load.t - check module loading and create testing directory

use Test::More tests => 1;

BEGIN { use_ok( 'POE::Adaptor::Net::LDAP' ); }

#my $object = POE::Adaptor::Net::LDAP->new ();
#isa_ok ($object, 'POE::Adaptor::Net::LDAP');


