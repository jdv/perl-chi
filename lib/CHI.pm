package CHI;
use 5.006;
use Carp;
use CHI::NullLogger;
use CHI::Util qw(require_dynamic);
use strict;
use warnings;

our $VERSION = '0.10';

our $Logger = CHI::NullLogger->new();    ## no critic

sub logger {
    my $self = shift;
    if (@_) {
        $Logger = shift;
    }
    return $Logger;
}

sub new {
    my ( $class, %params ) = @_;

    my $driver_class;
    if ( my $driver = delete( $params{driver} ) ) {
        $driver_class = "CHI::Driver::$driver";
    }
    else {
        $driver_class = delete( $params{driver_class} );
    }
    croak "missing required param 'driver' or 'driver_class'"
      unless defined $driver_class;

    # Load class if it hasn't been loaded or defined in-line already
    #
    unless ( $driver_class->can('fetch') ) {
        require_dynamic($driver_class);
    }

    return $driver_class->new(%params);
}

1;

__END__

=pod

=head1 NAME

CHI -- Unified cache interface

=head1 SYNOPSIS

    use CHI;

    # Choose a standard driver
    #
    my $cache = CHI->new( driver => 'Memory' );
    my $cache = CHI->new( driver => 'File', cache_root => '/path/to/root' );
    my $cache = CHI->new(
        driver     => 'FastMmap',
        root_dir   => '/path/to/root',
        cache_size => '1k'
    );
    my $cache = CHI->new(
        driver  => 'Memcached',
        servers => [ "10.0.0.15:11211", "10.0.0.15:11212" ]
    );
    my $cache = CHI->new(
        driver => 'Multilevel',
        subcaches => [
            { driver => 'Memory' },
            {
                driver  => 'Memcached',
                servers => [ "10.0.0.15:11211", "10.0.0.15:11212" ]
            }
        ],
    );

    # Create your own driver
    # 
    my $cache = CHI->new( driver_class => 'My::Special::Driver' );

    # (These drivers coming soon...)
    #
    my $cache = CHI->new( driver => 'DBI', dbh => $dbh, table => 'app_cache' );
    my $cache = CHI->new( driver => 'BerkeleyDB', root_dir => '/path/to/root' );

    # Basic cache operations
    #
    my $customer = $cache->get($name);
    if ( !defined $customer ) {
        $customer = get_customer_from_db($name);
        $cache->set( $name, $customer, "10 minutes" );
    }
    $cache->remove($name);

=head1 DESCRIPTION

CHI provides a unified caching API, designed to assist a developer in persisting data for
a specified period of time.

The CHI interface is implemented by driver classes that support fetching, storing and
clearing of data. Driver classes exist or will exist for the gamut of storage backends
available to Perl, such as memory, plain files, memory mapped files, memcached, and DBI.

CHI is intended as an evolution of DeWitt Clinton's L<Cache::Cache|Cache::Cache> package,
adhering to the basic Cache API but adding new features and addressing limitations in the
Cache::Cache implementation.

=for readme stop

=head1 CONSTRUCTOR

To create a new cache handle, call CHI-E<gt>new. It takes the following common options.
All are optional, except that either I<driver> or I<driver_class> must be passed.

=over

=item driver [STRING]

The name of a standard driver to drive the cache, for example "Memory" or "File".  CHI
will prefix the string with "CHI::Driver::".

=item driver_class [STRING]

The exact CHI::Driver subclass to drive the cache, for example "My::Memory::Driver".

=item namespace [STRING]

Identifies a namespace that all cache entries for this object will be in. This allows easy
separation of multiple, distinct caches without worrying about key collision.

Suggestions for easy namespace selection:

=over

=item *

In a class, use the class name:

    my $cache = CHI->new(namespace => __PACKAGE__, ...);

=item *

In a script, use the script's absolute path name:

    use Cwd qw(realpath);
    my $cache = CHI->new(namespace => realpath($0), ...);

=item *

In a web template, use the template name. For example, in Mason, $m-E<gt>cache will set
the namespace to the current component path.

=back

Defaults to 'Default' if not specified.

=item serializer [STRING|OBJECT]

An object to use for serializing data before storing it in the cache, and deserializing
data before retrieving it from the cache.

If this is a string, a L<Data::Serializer|Data::Serializer> object will be created, with
the string passed as the 'serializer' option. Common options include 'Storable',
'Data::Dumper', and 'YAML'.

Otherwise, this must be a L<Data::Serializer|Data::Serializer> object, or another object
that implements I<serialize()> and I<deserialize()>.

e.g.

    my $cache = CHI->new(serializer => 'Data::Dumper');
    my $cache = CHI->new(serializer => Data::Serializer->new(serializer => 'Data::Dumper', compress => 1));

The default is to use plain Storable.

=item expires_in [DURATION]

=item expires_at [NUM]

=item expires_variance [FLOAT]

Provide default values for the corresponding L</set> options.

=item on_get_error [STRING|CODEREF]

=item on_set_error [STRING|CODEREF]

How to handle runtime errors occurring during cache gets and cache sets, which may or may
not be considered fatal in your application. Options are:

=over

=item *

log (the default) - log an error using the currently set logger, or ignore if no logger is set - see L</LOGGING>

=item *

ignore - do nothing

=item *

warn - call warn() with an appropriate message

=item *

die - call die() with an appropriate message

=item *

I<coderef> - call this code reference with three arguments: an appropriate message, the key, and the original raw error message

=back

=back    

Some drivers will take additional constructor options. For example, the File driver takes
C<root_dir> and C<depth> options.

=head1 INSTANCE METHODS

The following methods can be called on any cache handle returned from CHI-E<gt>new(). They are implemented in the L<CHI::Driver|CHI::Driver> package.

=head2 Getting and setting

=over

=item get( $key, [option =E<gt> value, ...] )

Returns the data associated with I<$key>. If I<$key> does not exist or has expired, returns undef.
Expired items are not automatically removed and may be examined with L</get_object> or L</get_expires_at>.

I<$key> may be followed by one or more name/value parameters:

=over

=item expire_if [CODEREF]

If I<$key> exists and has not expired, call code reference with the
L<CHI::CacheObject|CHI::CacheObject> as a single parameter. If code returns a true value,
expire the data. For example, to expire the cache if I<$file> has changed since
the value was computed:

    $cache->get('foo', expire_if => sub { $_[0]->created_at < (stat($file))[9] });

=item busy_lock [DURATION]

If the value has expired, set its expiration time to the current time plus the specified
L<duration|/DURATION EXPRESSIONS> before returning undef.  This is used to prevent
multiple processes from recomputing the same expensive value simultaneously. The problem
with this technique is that it doubles the number of writes performed - see
L</expires_variance> for another technique.

=back

=item set( $key, $data, [$expires_in | "now" | "never" | options] )

Associates I<$data> with I<$key> in the cache, overwriting any existing entry.

The third argument to C<set> is optional, and may be either a scalar or a hash reference.
If it is a scalar, it may be the string "now", the string "never", or else a duration
treated as an I<expires_in> value described below. If it is a hash reference, it may
contain one or more of the following options. Most of these options can be provided with
defaults in the cache constructor.

=over

=item expires_in [INT]

Amount of time (in seconds) until this data expires.

=item expires_at [NUM]

The epoch time at which the data expires.

=item expires_variance [FLOAT]

Controls the variable expiration feature, which allows items to expire a little earlier
than the stated expiration time to help prevent cache miss stampedes.

Value is between 0.0 and 1.0, with 0.0 meaning that items expire exactly when specified
(feature is disabled), and 1.0 meaning that items might expire anytime from now til the
stated expiration time. The default is 0.0. A setting of 0.10 to 0.25 would introduce a
small amount of variation without interfering too much with intended expiration times.

The probability of expiration increases as a function of how far along we are in the
potential expiration window, with the probability being near 0 at the beginning of the
window and approaching 1 at the end.

For example, in all of the following cases, an item might be considered expired any time
between 15 and 20 minutes, with about a 20% chance at 16 minutes, a 40% chance at 17
minutes, and a 100% chance at 20 minutes.

    my $cache = CHI->new ( ..., expires_variance => 0.25, ... );
    $cache->set($key, $value, '20 min');
    $cache->set($key, $value, { expires_at => time() + 20*60 });

    my $cache = CHI->new ( ... );
    $cache->set($key, $value, { expires_in => '20 min', expires_variance => 0.25 });

CHI will make a new probabilistic choice every time it needs to know whether an item has
expired (i.e. it does not save the results of its determination), so you can get
situations like this:

    my $value = $cache->get($key);     # returns undef (indicating expired)
    my $value = $cache->get($key);     # returns valid value this time!

    if ($cache->is_valid($key))        # returns undef (indicating expired)
    if ($cache->is_valid($key))        # returns true this time!

Typical applications won't be affected by this, since the object is recomputed as soon
as it is determined to be expired. But it's something to be aware of.

=back

=item compute( $key, $code, $set_options )

Combines the C<get> and C<set> operations in a single call. Attempts to get I<$key>;
if successful, returns the value. Otherwise, calls I<$code> and uses the
return value as the new value for I<$key>, which is then returned. I<$set_options>
is a scalar or hash reference, used as the third argument to set.

This method will eventually support the ability to recompute a value in the background
just before it actually expires, so that users are not impacted by recompute time.

=back

=head2 Removing and expiring

=over

=item remove( $key )

Remove the data associated with the I<$key> from the cache.

=item expire( $key )

If I<$key> exists, expire it by setting its expiration time into the past. Does not necessarily
remove the data.

=item expire_if ( $key, $code )

If I<$key> exists, call code reference I<$code> with the L<CHI::CacheObject|CHI::CacheObject> as a single
parameter. If I<$code> returns a true value, expire the data. e.g.

    $cache->expire_if('foo', sub { $_[0]->created_at < (stat($file))[9] });

=back

=head2 Inspecting keys

=over

=item is_valid( $key )

Returns a boolean indicating whether I<$key> exists in the cache and has not
expired. Note: Expiration may be determined probabilistically if L</expires_variance>
was used.

=item exists_and_is_expired( $key )

Returns a boolean indicating whether I<$key> exists in the cache and has expired.  Note:
Expiration may be determined probabilistically if L</expires_variance> was used.

=item get_expires_at( $key )

Returns the epoch time at which I<$key> definitively expires. Returns undef if the key
does not exist or it has no expiration time.

=item get_object( $key )

Returns a L<CHI::CacheObject|CHI::CacheObject> object containing data about the entry associated with
I<$key>, or undef if no such key exists. The object will be returned even if the entry
has expired, as long as it has not been removed.

=back

=head2 Namespace operations

=over

=item clear( )

Remove all entries from the namespace.

=item get_keys( )

Returns a list of keys in the namespace. This may or may not include expired keys, depending on the driver.

=item is_empty( )

Returns a boolean indicating whether the namespace is empty, based on get_keys().

=item purge( )

Remove all entries that have expired from the namespace associated
with this cache instance. Warning: May be very inefficient, depending on the
number of keys and the driver.

=item get_namespaces( )

Returns a list of namespaces associated with the cache. This may or may not include empty namespaces, depending on the driver.

=back

=head2 Multiple key/value operations

The methods in this section process multiple keys and/or values at once. By default these
are implemented with the obvious map operations, but some cache drivers
(e.g. L<Cache::Memcached|Cache::Memcached>) can override them with more efficient implementations.

=over

=item get_multi_arrayref( $keys )

Get the keys in list reference I<$keys>, and return a list reference of the same length
with corresponding values or undefs.

=item get_multi_array( $keys )

Like L</get_multi_arrayref>, but returns an array instead of an array reference.

=item get_multi_hashref( $keys )

Like L</get_multi_arrayref>, but returns a hash reference with each key in I<$keys> mapping to
its corresponding value or undef.

=item set_multi( $key_values, $set_options )

Set the multiple keys and values provided in hash reference I<$key_values>. I<$set_options>
is a scalar or hash reference, used as the third argument to set.

=item remove_multi( $keys )

Removes the keys in list reference I<$keys>.

=item dump_as_hash( )

Returns a hash reference containing all the non-expired keys and values in the cache.

=back

=head2 Property accessors

There is a read-only accessor for C<namespace>, and read/write accessors for
C<expires_in>, C<expires_at>, C<expires_variance>, C<on_get_error>, and C<on_set_error>.

=head1 DURATION EXPRESSIONS

Duration expressions, which appear in the L</set> command and various other parts of the
API, are parsed by L<Time::Duration::Parse|Time::Duration::Parse>. A duration is either a
plain number, which is treated like a number of seconds, or a number and a string
representing time units where the string is one of:

    s second seconds sec secs
    m minute minutes min mins
    h hr hour hours
    d day days
    w week weeks
    M month months
    y year years

e.g. the following are all valid duration expressions:

    25
    3s
    5 seconds
    1 minute and ten seconds
    1 hour

=for readme continue

=head1 AVAILABILITY OF DRIVERS

The following drivers are currently available as part of this distribution. Other drivers
can be found on CPAN by searching for "CHI::Driver".

=over

=item *

L<CHI::Driver::Memory|CHI::Driver::Memory> - In-process memory based cache

=item *

L<CHI::Driver::File|CHI::Driver::File> - File-based cache using one file per entry in a multi-level directory structure

=item *

L<CHI::Driver::FastMmap|CHI::Driver::FastMmap> - Shared memory interprocess cache via mmap'ed files

=item *

L<CHI::Driver::FastMmap|CHI::Driver::Null> - Dummy cache in which nothing is stored

=item *

L<CHI::Driver::Multilevel|CHI::Driver::Multilevel> - Cache formed from several subcaches chained together

=item *

L<CHI::Driver::CacheCache|CHI::Driver::CacheCache> - CHI wrapper for Cache::Cache

=back

=for readme stop

=head1 DEVELOPING NEW DRIVERS

See L<CHI::Driver::Development|CHI::Driver::Development> for information on developing new drivers.

=head1 LOGGING

If given a logger object, CHI will log events at various levels - for example, a debug log
message for every cache get and set. To specify the logger object:

    CHI->logger($logger_object);   # Warning: Temporary API, see below

The object must provide the methods

    debug, info, warning, error, fatal

for logging, and

    is_debug, is_info, is_warning, is_error, is_fatal

for checking whether a message would be logged at that level. This is compatible with L<Log::Log4perl|Log::Log4perl>
and L<Catalyst::Log|Catalyst::Log> among others.

Warning: CHI-E<gt>logger is a temporary API. The intention is to replace this with Log::Any
(L<http://use.perl.org/~jonswar/journal/34366>).

=for readme continue

=head1 RELATION TO OTHER MODULES

=head2 Cache::Cache

CHI is intended as an evolution of DeWitt Clinton's L<Cache::Cache|Cache::Cache> package.
It starts with the same basic API (which has proven durable over time) but addresses some
implementation shortcomings that cannot be fixed in Cache::Cache due to backward
compatibility concerns.  In particular:

=over

=item Performance

Some of Cache::Cache's subclasses (e.g. L<Cache::FileCache|Cache::FileCache>) have been
justifiably criticized as inefficient. CHI has been designed from the ground up with
performance in mind, both in terms of general overhead and in the built-in driver classes.
Method calls are kept to a minimum, data is only serialized when necessary, and metadata
such as expiration time is stored in packed binary format alongside the data.

As an example, using Rob Mueller's cacheperl benchmarks, CHI's file driver runs 3 to 4
times faster than Cache::FileCache.

=item Ease of subclassing

New Cache::Cache subclasses can be tedious to create, due to a lack of code refactoring,
the use of non-OO package subroutines, and the separation of "cache" and "backend"
classes. With CHI, the goal is to make the creation of new drivers as easy as possible,
roughly the same as writing a TIE interface to your data store.  Concerns like
serialization and expiration options are handled by the driver base class so that
individual drivers don't have to worry about them.

=item Increased compatibility with cache implementations

Probably because of the reasons above, Cache::Cache subclasses were never created for some
of the most popular caches available on CPAN, e.g. L<Cache::FastMmap|Cache::FastMmap> and L<Cache::Memcached|Cache::Memcached>.
CHI's goal is to be able to support these and other caches with a minimum performance
overhead and minimum of glue code required.

=back

=head2 Cache::Memcached, Cache::FastMmap, etc.

CPAN sports a variety of full-featured standalone cache modules representing particular
backends. CHI does not reinvent these but simply wraps them with an appropriate
driver. For example, CHI::Driver::Memcached and CHI::Driver::FastMmap are thin layers
around Cache::Memcached and Cache::FastMmap.

Of course, because these modules already work on their own, there will be some overlap.
Cache::FastMmap, for example, already has code to serialize data and handle expiration
times. Here's how CHI resolves these overlaps.

=over

=item Serialization

CHI handles its own serialization, passing a flat binary string to the underlying cache
backend.

=item Expiration

CHI packs expiration times (as well as other metadata) inside the binary string passed to
the underlying cache backend. The backend is unaware of these values; from its point of
view the item has no expiration time. Among other things, this means that you can use CHI
to examine expired items (e.g. with $cache-E<gt>get_object) even if this is not supported
natively by the backend.

At some point CHI will provide the option of explicitly notifying the backend of the
expiration time as well. This might allow the backend to do better storage management,
etc., but would prevent CHI from examining expired items.

=back

Naturally, using CHI's FastMmap or Memcached driver will never be as time or storage
efficient as simply using Cache::FastMmap or Cache::Memcached.  In terms of performance,
we've attempted to make the overhead as small as possible, on the order of 5% per get or
set (benchmarks coming soon). In terms of storage size, CHI adds about 16 bytes of
metadata overhead to each item. How much this matters obviously depends on the typical
size of items in your cache.

=head1 SUPPORT AND DOCUMENTATION

Questions and feedback are welcome, and should be directed to the perl-cache mailing list:

    http://groups.google.com/group/perl-cache-discuss

Bugs and feature requests will be tracked at RT:

    http://rt.cpan.org/NoAuth/Bugs.html?Dist=CHI

The latest source code can be browsed and fetched at:

    http://github.com/jonswar/perl-chi/tree/master
    git clone git://github.com/jonswar/perl-chi.git

=head1 TODO

=over

=item *

Perform cache benchmarks comparing both CHI and non-CHI cache implementations

=item *

Release BerkeleyDB and DBI drivers as separate CPAN distributions

=item *

Add docs comparing various strategies for reducing miss stampedes and cost of recomputes

=item *

Add expires_next syntax (e.g. expires_next => 'hour')

=item *

Support automatic serialization and escaping of keys

=item *

Create XS versions of main functions in Driver.pm (e.g. get, set)

=back

=head1 ACKNOWLEDGMENTS

Thanks to Dewitt Clinton for the original Cache::Cache, to Rob Mueller for the Perl cache
benchmarks, and to Perrin Harkins for the discussions that got this going.

CHI was originally designed and developed for the Digital Media group of the Hearst
Corporation, a diversified media company based in New York City.  Many thanks to Hearst
management for agreeing to this open source release.

=head1 AUTHOR

Jonathan Swartz

=head1 SEE ALSO

L<Cache::Cache|Cache::Cache>, L<Cache::Memcached|Cache::Memcached>, L<Cache::FastMmap|Cache::FastMmap>

=head1 COPYRIGHT & LICENSE

Copyright (C) 2007 Jonathan Swartz.

CHI is provided "as is" and without any express or implied warranties, including, without
limitation, the implied warranties of merchantibility and fitness for a particular
purpose.

This program is free software; you can redistribute it and/or modify it under the same
terms as Perl itself.

=cut
