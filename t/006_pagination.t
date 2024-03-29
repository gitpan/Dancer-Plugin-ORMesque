use strict;
use warnings;
use Test::More tests => 7, import => ['!pass'];
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

my $cd = db->cd;

ok "Data::Page" eq ref($cd->pager), 'pager set';
ok $cd->read({},[],2,1), 'limit no fail';

#$cd->{dbh}->{dbh}->trace(1);

ok $cd->page(1,2)->read(), 'paging no fail page 1';
#warn to_dumper [$cd->hashes];

ok $cd->page(2,2)->read(), 'paging no fail page 2';
#warn to_dumper [$cd->hashes];

ok $cd->page(3,2)->read(), 'paging no fail page 3';
#warn to_dumper [$cd->hashes];