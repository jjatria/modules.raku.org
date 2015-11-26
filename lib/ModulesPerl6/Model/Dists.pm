package ModulesPerl6::Model::Dists;

use Mojo::Base -base;

use Carp             qw/croak/;
use File::Spec::Functions qw/catfile/;
use FindBin; FindBin->again;
use Mojo::Collection qw/c/;
use Mojo::Util       qw/trim/;
use ModulesPerl6::Model::Dists::Schema;
use ModulesPerl6::Metrics::Kwalitee;

has db_file => sub {
    $ENV{MODULESPERL6_DB_FILE}// catfile $FindBin::Bin, qw/.. modulesperl6.db/;
};

has _db     => sub {
    ModulesPerl6::Model::Dists::Schema->connect(
        'dbi:SQLite:' . shift->db_file,
        '', '', { sqlite_unicode => 1 },
    );
};

sub _find {
    my $self   = shift;
    my $is_hri = shift;
    my $what   = shift // {};
    ref $what eq 'HASH' or croak 'find only accepts a hashref';

    %$what = map {
        ref $what->{$_} eq 'SCALAR'
            ? ( $_ => { -like => "%${ $what->{$_} }%" } )
            : $what->{$_}
                ? ( $_ => $what->{$_} ) : ()
    } qw/name  author_id  travis_status  description/;

    my $res = $self->_db->resultset('Dist')->search($what,
        $is_hri ? {
            result_class => 'DBIx::Class::ResultClass::HashRefInflator'
        } : ()
    );

    return $is_hri ? c $res->all : $res;
}

sub add {
    my ( $self, @data ) = @_;
    @data or return $self;

    my $db = $self->_db;
    for my $dist ( @data ) {
        $_ = trim $_//'' for values %$dist;
        $dist->{travis_status} ||= 'not set up';
        $dist->{date_updated}  ||= 0;
        $dist->{date_added}    ||= 0;
        $dist->{kwalitee} //= ModulesPerl6::Metrics::Kwalitee->new->kwalitee({
            map +( $_ => $dist->{$_} ),
                qw/has_readme  panda  has_tests  travis/,
        });

        $db->resultset('Dist')->update_or_create({
            travis   => { status => $dist->{travis_status} },
            author => { # use same field for both, for now. TODO:fetch realname
                author_id => $dist->{author_id}, name => $dist->{author_id},
            },
            dist_build_id => { id => $dist->{build_id} },
            map +( $_ => $dist->{$_} ),
                qw/name  url  description  stars  issues  kwalitee
                    date_updated  date_added/,
        });
    }

    $self;
}

sub deploy {
    my $self = shift;
    $self->_db->deploy;

    $self;
}

sub find {
    my $self = shift;
    return $self->_find(1, @_);
}

sub remove {
    my $self = shift;
    $self->_find(0, @_)->delete_all;

    $self;
}

sub remove_old {
    my ( $self, $build_id ) = @_;
    length $build_id or croak 'Missing Build ID to keep';

    my $res = $self->_db->resultset('Dist')->search({
        build_id => { '!=', $build_id }
    });
    my $num_deleted = $res->all;
    $res->delete_all;

    $num_deleted;
}

1;

__END__

=encoding utf8

=for stopwords dists

=head1 NAME

ModulesPerl6::Model::Dists - model representing Perl 6 distributions

=head1 SYNOPSIS

    my $m = ModulesPerl6::Model::Dists->new( db_file => 'mydb.db' )->deploy;
    $m->add( $dist );
    say $_->{url} for $m->find({ name => 'Dist1' })->each;
    $m->remove({ name => 'Dist1' });
    $m->remove_old('rvOZAHmQ5RGKE79B+wjaYA==')

=head1 DESCRIPTION

This module is used to access and manipulate the database of Perl 6
distributions that is built by the build script.

=head1 METHODS

=head2 C<new>

    my $m = ModulesPerl6::Model::Dists->new;

    my $m = ModulesPerl6::Model::Dists->new( db_file => 'mydb.db' );

Creates and returns a new C<ModulesPerl6::Model::Dists> object. Takes
these arguments:

=head3 C<db_file>

    my $m = ModulesPerl6::Model::Dists->new( db_file => 'mydb.db' );

B<Optional>. Specifies the filename of the SQLite database with dist info.
B<Defaults to:> the value of C<MODULESPERL6_DB_FILE> environmental variable,
if set, or C<modulesperl6.db>.

=head2 C<add>

    $m->add({
        name         => 'Dist1',
        url          => 'https://github.com/perl6/modules.perl6.org/',
        description  => 'Test Dist1',
        author_id    => 'Dynacoder',
        has_readme   => 1,
        panda        => 2,
        has_tests    => 1,
        travis_status=> 'passing',
        stars        => 42,
        issues       => 12,
        date_updated => 1446999664,
        date_added   => 1446694664,
        build_id     => 'rvOZAHmQ5RGKE79B+wjaYA==',
    });

    $m->add( $dist1, $dist2 );

Add new dist to the database. Takes a list of hashrefs, where each hashref
represents a dist. The keys of the hashref are as follows:

=head3 C<name>

Name of the dist.

=head3 C<url>

URL of the dist's GitHub repo.

=head3 C<description>

Short description of the dist.

=head3 C<author_id>

Dists's "authority".

=head3 C<has_readme>

Boolean: does the dist have README file?

=head3 C<panda>

Takes values C<0> (dist is not conforming to latest specs),
C<1> (dist conforms to specs, except for S11), or C<2> (dist fully conforms
to current spec).

=head3 C<has_tests>

Boolean: does the dist have tests?

=head3 C<travis_status>

Takes a valid string of L<Travis-CI.org|https://travis-ci.org/> build status
(e.g. C<passing>, C<failing>, C<unknown>, etc). Will accept any value.
If not specified, will be set to C<not set up>.

=head3 C<stars>

Number of dists's "Stargazers" (people who starred the repo on GitHub).

=head3 C<issues>

Number of open Issues the dist has on GitHub

=head3 C<date_updated>

Unix epoch of when the dist was last updated (usually, date of last
commit on GitHUb)

=head3 C<date_added>

Unix epoch of when the dist was added to the Perl 6 Ecosystem (this is NOT
the same as when the repo was first created on GitHub).

=head3 C<build_id>

A string of text that indentifies the build ID: a random string used
by the database updater script to identify each run. You'll likely want
to use something like L<Data::GUID/"to_base64"> as the ID.

=head2 C<deploy>

    $m->deploy

B<Takes> no arguments. B<Returns> its invocant. Deploys (creates) the SQL
tables needed for this module to operate. B<Will die> if they already exists.

=head2 C<find>

    my $dists = $m->find; # return all dists in the db
    my $dists = $m->find({ name => 'Dist1'  });  # exact match
    my $dists = $m->find({ name => \'Dist1' }); # SQL "like" match
    my $dist  = $m->find({
        name        => \'Dist',
        description => \'Test Dist1',
    })->first;

Searches the database for dists that match given criteria. B<Returns>
a, possibly empty, L<Mojo::Collection> object containing found dists
as hashrefs. Each hashref will contain the same keys and type of values
as were given to L</add> method, B<except> the L</has_readme>, L</has_tests>,
and L</panda> metrics are combined into a Kwalitee metric ranging from
C<0> to C<100>.

B<Without arguments>, returns all dists in the database.
B<Takes> a hashref specifying search criteria. If the search criteria a
string, it will be matched exactly. If it's a scalar reference, its value
will be matched partially and case-insensitively (i.e. something like
C<m/.*foo.*/i>). More than one criteria can be specified. Valid criteria are:

=head3 C<name>

Search by the name of the distribution

=head3 C<description>

Search by the description of the dist

=head3 C<author_id>

Search by the authority of the dist

=head3 C<travis_status>

Search by the Travis CI status

=head2 C<remove>

    $m->remove({ name => 'Dist1' });

B<Takes> the same argument as L</find> and any matching dists will be deleted
from the database. B<Returns> its invocant.

=head2 C<remove_old>

    $m->remove_old('rvOZAHmQ5RGKE79B+wjaYA==');

B<Takes> a mandatory argument, which is the build ID of the dists to
KEEP in the database. Any build IDs that do not match this will be deleted.
A likely usage of this would be to call this method after rebuilding
the database to remove any dists that were not in the new build list.

=head1 PRIVATE ATTRIBUTES

B<These attributes are documented for developers working on this module.
Do NOT use these attributes outside of this package.>

=head2 C<_db>

Contains C<ModulesPerl6::Model::Dists::Schema> L<DBIx::Class::Schema>
object.

=head1 PRIVATE METHODS

B<These methods are documented for developers working on this module.
Do NOT use these methods outside of this package.>

=head2 C<_find>

    $self->_find(1, { name => 'Dist1'});

Used by L</find> and L</remove> methods. Second argument is the search
criteria hashref (if not specified, empty one will be used). The first argument
is a boolean that specifies whether the database search result objects should
be converted into hashrefs using L<DBIx::Class::ResultClass::HashRefInflator>
result class.

=head1 CONTACT INFORMATION

Original version of this module was written by Zoffix Znet
(L<https://github.com/zoffixznet/>, C<Zoffix> on irc.freenode.net).

=head1 LICENSE

You can use and distribute this module under the same terms as Perl itself.
