use strict;
use warnings;
use Test::More tests => 4, import => ['!pass'];
use Test::Exception;
use FindBin;

BEGIN {
    use_ok 'Dancer', ':syntax';
    use_ok 'Dancer::Plugin::ORMesque';
}

set plugins     => {
        'ORMesque' => {
            foo => {
                dsn => "dbi:SQLite:" . $FindBin::Bin . "/001_database.db"
            }
        }
};

eval { require DBD::SQLite };
if ($@) {
    plan skip_all => 'DBD::SQLite is required to run these tests';
}

my $cd = db->cd->read;

ok $DBIx::Simple::VERSION eq '1.32_MOD', 'ORMesque has the modified DBIx::Simple class';
ok "SQL::Abstract::Limit" eq ref($cd->{dbh}->{abstract}), "SQL::Abstract::Limit module installed";