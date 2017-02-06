use strict;
use warnings;

use Test::More;
use Test2::API qw/intercept/;

my $events = intercept {
    subtest foo => sub {
        ok(1, "pass");
    };
};

my $st = $events->[-1];
isa_ok($st, 'Test2::Event::Subtest');
ok(my $id = $st->nest_id, "got an id");
for my $se (@{$st->nest_events}) {
    is($se->nest_parent, $id, "set nest_parent on child event");
}

done_testing;
