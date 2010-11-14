use strict;
use warnings;
use Test::More tests => 5, import => ['!pass'];
use Test::Exception;
use FindBin;

BEGIN {
    use lib "$FindBin::Bin/lib";
    use_ok 'Dancer', ':syntax';
    use_ok 'Dancer::Plugin::Database';
    use_ok 'Dancer::Plugin::ORMesque';
}

set session     => "YAML";
set session_dir => $FindBin::Bin . "/sessions";
set plugins     => {
        'Database' => {
                driver   => 'SQLite',
                database => "$FindBin::Bin/001_database.db"
        }
};

eval { require DBD::SQLite };
if ($@) {
    plan skip_all => 'DBD::SQLite is required to run these tests';
}

my $cd = dbi->cd->read;

ok $DBIx::Simple::VERSION eq '1.32_MOD', 'ORMesque has the modified DBIx::Simple class';
ok "SQL::Abstract::Limit" eq ref($cd->{dbh}->{abstract}), "SQL::Abstract::Limit module installed";