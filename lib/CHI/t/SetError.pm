package CHI::t::SetError;
use CHI::Test;
use strict;
use warnings;
use base qw(CHI::Test::Class);

sub readonly_cache {
    my ($on_set_error) = @_;

    return CHI->new(
        driver_class => 'CHI::Test::Driver::Readonly',
        on_set_error => $on_set_error
    );
}

sub test_set_errors : Test(9) {
    my ( $key, $value ) = ( 'medium', 'medium' );

    my $log = CHI::Test::Logger->new();
    CHI->logger($log);

    my $cache;

    $cache = readonly_cache('ignore');
    lives_ok( sub { $cache->set( $key, $value ) }, "ignore - lives" );
    ok( !defined( $cache->get($key) ), "ignore - miss" );

    $cache = readonly_cache('die');
    throws_ok(
        sub { $cache->set( $key, $value ) },
        qr/read-only cache/,
        "die - dies"
    );
    ok( !defined( $cache->get($key) ), "die - miss" );

    $log->clear();
    $cache = readonly_cache('log');
    lives_ok( sub { $cache->set( $key, $value ) }, "log - lives" );
    ok( !defined( $cache->get($key) ), "log - miss" );
    $log->contains_ok(qr/cache get for .* key='medium', .*: MISS/);
    $log->contains_ok(qr/error setting key 'medium' in .*: read-only cache/);
    $log->empty_ok();
}

1;
