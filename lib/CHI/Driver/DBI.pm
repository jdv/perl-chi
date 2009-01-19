package CHI::Driver::DBI;

use DBI;
use DBI::Const::GetInfoType;
use Moose;
use strict;
use warnings;

# TODO:  For pg see "upsert" - http://www.postgresql.org/docs/current/static/plpgsql-control-structures.html#PLPGSQL-UPSERT-EXAMPLE

extends 'CHI::Driver';

=head1 NAME

CHI::Driver::DBI - db cache backend

=head1 SYNOPSIS

 use CHI;

 my $dbh   = DBI->connect(...);
 my $cache = CHI->new( driver => 'DBI', dbh => $dbh, );
 OR
 my $cache = CHI->new( driver => 'DBI', dbh => $dbh, dbh_ro => $dbh_ro, );

=head1 DESCRIPTION

This driver uses a single table to store the cache.
The newest versions of MySQL and SQLite work are known
to work.  Other RDBMSes should work.

This driver may seem ironic or stupid to some.  It was
motivated by a need to have a cache that was solid.

=head1 ATTRIBUTES

=over

=item dbh

The main, or rw, DBI handle used to communicate with the db.
If a dbh_ro handle is defined then this handle will only be used
for writing.

=cut

has 'dbh' => ( is => 'rw', isa => 'DBI::db', required => 1, );

=item dbh_ro

The optional DBI handle used for read-only operations.  This is
to support master/slave RDBMS setups.

=cut

has 'dbh_ro' => ( is => 'rw', isa => 'DBI::db', );

=item table

The name of the cache table.  Defaults to "chi_driver_dbi".

=cut

has 'table' => ( is => 'rw', isa => 'Str', lazy_build => 1, );

=item sql_strings

Hashref of SQL strings to use in the different cache operations.
The strings are built depending on the RDBMS that dbh is attached to.

=back

=cut

has 'sql_strings' => ( is => 'rw', isa => 'HashRef', lazy_build => 1, );

__PACKAGE__->meta->make_immutable;

=head1 METHODS

=over

=item BUILD

Standard issue Moose BUILD method.  Used to build the sql_strings
and to create the db table.  The table creation can be skipped if
the create_table driver param is set to false.  For Mysql and SQLite
the statement is "create if not exists..." so its generally harmless.

=cut

sub BUILD {
    my ( $self, $args, ) = @_;

    $self->sql_strings;

    unless ( defined $args->{create_table} && $args->{create_table} ) {
        $self->{dbh}->do( $self->{sql_strings}->{create} )
          or croak $self->{dbh}->errstr;
    }

    return;
}

sub _build_table {
    my ( $self, ) = @_;

    return 'chi_driver_dbi';
}

sub _build_sql_strings {
    my ( $self, ) = @_;

    my $qc = $self->dbh->get_info( $GetInfoType{SQL_IDENTIFIER_QUOTE_CHAR} );
    my $t  = $self->table;
    my $db = $self->dbh->get_info( $GetInfoType{SQL_DBMS_NAME} );

    my $strings = {
        fetch => "select ${qc}value${qc} from $qc$t$qc"
          . " where ${qc}namespace${qc} = ? and ${qc}key${qc} = ?",
        store => "insert into $qc$t$qc"
          . " ( ${qc}value${qc}, ${qc}namespace${qc}, ${qc}key${qc} )"
          . " values ( ?, ?, ? )",
        store2 => "update $qc$t$qc"
          . " set ${qc}value${qc} = ? where ${qc}namespace${qc} = ?"
          . " and ${qc}key${qc} = ?",
        remove => "delete from $qc$t$qc"
          . " where ${qc}namespace${qc} = ? and ${qc}key${qc} = ?",
        clear    => "delete from $qc$t$qc where ${qc}namespace${qc} = ?",
        get_keys => "select distinct ${qc}key${qc} from $qc$t$qc"
          . " where ${qc}namespace${qc} = ?",
        get_namespaces => "select distinct ${qc}namespace${qc} from $qc$t$qc",
        create         => "create table if not exists $qc$t$qc ("
          . " ${qc}namespace${qc} varchar( 100 ),"
          . " ${qc}key${qc} varchar( 600 ), ${qc}value${qc} text,"
          . " primary key ( ${qc}namespace${qc}, ${qc}key${qc} ) )",
    };

    if ( $db eq 'MySQL' ) {
        $strings->{store} =
            "replace into $qc$t$qc"
          . " ( ${qc}value${qc}, ${qc}namespace${qc}, ${qc}key${qc} )"
          . " values ( ?, ?, ? )";
        delete $strings->{store2};
    }
    elsif ( $db eq 'SQLite' ) {
        $strings->{store} =
            "insert or replace into $qc$t$qc"
          . " ( ${qc}value${qc}, ${qc}namespace${qc}, ${qc}key${qc} )"
          . " values ( ?, ?, ? )";
        delete $strings->{store2};
    }

    return $strings;
}

=item fetch

=cut

sub fetch {
    my ( $self, $key, ) = @_;

    my $dbh = $self->{dbh_ro} ? $self->{dbh_ro} : $self->{dbh};
    my $sth = $dbh->prepare_cached( $self->{sql_strings}->{fetch} )
      or croak $dbh->errstr;
    $sth->execute( $self->{namespace}, $key ) or croak $sth->errstr;
    my $results = $sth->fetchall_arrayref;

    return $results->[0]->[0];
}

=item store

=cut

sub store {
    my ( $self, $key, $data, ) = @_;

    my $sth = $self->{dbh}->prepare_cached( $self->{sql_strings}->{store} );
    unless ( $sth->execute( $data, $self->{namespace}, $key ) ) {
        if ( $self->{sql_strings}->{store2} ) {
            my $sth =
              $self->{dbh}->prepare_cached( $self->{sql_strings}->{store2} )
              or croak $self->{dbh}->errstr;
            $sth->execute( $data, $self->{namespace}, $key )
              or croak $sth->errstr;
        }
    }
    $sth->finish;

    return;
}

=item remove

=cut

sub remove {
    my ( $self, $key, ) = @_;

    my $sth = $self->dbh->prepare_cached( $self->{sql_strings}->{remove} )
      or croak $self->{dbh}->errstr;
    $sth->execute( $self->namespace, $key ) or croak $sth->errstr;
    $sth->finish;

    return;
}

=item clear

=cut

sub clear {
    my ( $self, $key, ) = @_;

    my $sth = $self->{dbh}->prepare_cached( $self->{sql_strings}->{clear} )
      or croak $self->{dbh}->errstr;
    $sth->execute( $self->namespace ) or croak $sth->errstr;
    $sth->finish;

    return;
}

=item get_keys

=cut

sub get_keys {
    my ( $self, ) = @_;

    my $dbh = $self->{dbh_ro} ? $self->{dbh_ro} : $self->{dbh};
    my $sth = $dbh->prepare_cached( $self->{sql_strings}->{get_keys} )
      or croak $dbh->errstr;
    $sth->execute( $self->namespace ) or croak $sth->errstr;
    my $results = $sth->fetchall_arrayref( [0] );
    $_ = $_->[0] for @{$results};

    return @{$results};
}

=item get_namespaces

=back

=cut

sub get_namespaces {
    my ( $self, ) = @_;

    my $dbh = $self->{dbh_ro} ? $self->{dbh_ro} : $self->{dbh};
    my $sth = $dbh->prepare_cached( $self->{sql_strings}->{get_namespaces} )
      or croak $dbh->errstr;
    $sth->execute or croak $sth->errstr;
    my $results = $sth->fetchall_arrayref( [0] );
    $_ = $_->[0] for @{$results};

    return @{$results};
}

=head1 Author

Justin DeVuyst

=head1 COPYRIGHT & LICENSE

Copyright (C) Justin DeVuyst

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
