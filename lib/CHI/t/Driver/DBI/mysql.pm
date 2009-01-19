package CHI::t::Driver::DBI::mysql;

use strict;
use warnings;
use CHI::Test;
use DBI;
use base qw(CHI::t::Driver);

sub testing_driver_class { 'CHI::Driver::DBI' }

sub new_cache_options {
    my $self = shift;

    my $dbh = DBI->connect(
        'dbi:mysql:database=test',
        '', '',
        {
            RaiseError => 0,
            PrintError => 0,
        }
    );

    return ( $self->SUPER::new_cache_options(), dbh => $dbh );
}

1;
