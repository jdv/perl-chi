package CHI::Util;
use Carp;
use Data::Dumper;
use Data::UUID;
use File::Spec::Functions qw(catdir catfile);
use Time::Duration::Parse;
use strict;
use warnings;
use base qw(Exporter);

our @EXPORT_OK = qw(
  dp
  dump_one_line
  fast_catdir
  fast_catfile
  parse_duration
  require_dynamic
  unique_id
);

sub _dump_value_with_caller {
    my ($value) = @_;

    my $dump =
      Data::Dumper->new( [$value] )->Indent(1)->Sortkeys(1)->Quotekeys(0)
      ->Terse(1)->Dump();
    my @caller = caller(1);
    return sprintf( "[dp at %s line %d.] [%d] %s\n",
        $caller[1], $caller[2], $$, $dump );
}

sub dp {
    print STDERR _dump_value_with_caller(@_);
}

sub dump_one_line {
    my ($value) = @_;

    return Data::Dumper->new( [$value] )->Indent(0)->Sortkeys(1)->Quotekeys(0)
      ->Terse(1)->Dump();
}

sub require_dynamic {
    my ($class) = @_;

    eval "require $class";    ## no critic (ProhibitStringyEval)
    croak $@ if $@;
}

{

    # For efficiency, use Data::UUID to generate an initial unique id, then suffix it to
    # generate a series of 0x10000 unique ids. Not to be used for hard-to-guess ids, obviously.

    my $ug = Data::UUID->new();
    my $uuid;
    my $suffix = 0;

    sub unique_id {
        if ( !$suffix || !defined($uuid) ) {
            $uuid = $ug->create_hex();
        }
        my $hex = sprintf( '%s%04x', $uuid, $suffix );
        $suffix = ( $suffix + 1 ) & 0xffff;
        return $hex;
    }
}

{
    my $File_Spec_Using_Unix = $File::Spec::ISA[0] eq 'File::Spec::Unix';

    sub fast_catdir {
        return $File_Spec_Using_Unix ? join( "/", @_ ) : catdir(@_);
    }

    sub fast_catfile {
        return $File_Spec_Using_Unix ? join( "/", @_ ) : catfile(@_);
    }
}

1;
