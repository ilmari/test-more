use strict;
use warnings;
use Test2::Tools::Tiny;

use Test2::Event();

{

    package My::MockEvent;

    use base 'Test2::Event';
    use Test2::Util::HashBase qw/foo bar baz/;
}

ok(My::MockEvent->can($_), "Added $_ accessor") for qw/foo bar baz/;

my $one = My::MockEvent->new(trace => 'fake');

tests meta => sub {
    ok(!$one->get_meta('xxx'), "no meta-data associated for key 'xxx'");

    $one->set_meta('xxx', '123');

    is($one->meta('xxx'), '123', "got meta-data");

    is($one->meta('xxx', '321'), '123', "did not use default");

    is($one->meta('yyy', '1221'), '1221', "got the default");

    is($one->meta('yyy'), '1221', "last call set the value to the default for future use");
};

tests legacy => sub {
    ok(!$one->increments_count, "inrements_count is false by default");

    is($one->diagnostics, 0, "Not diagnostics by default");

    ok(!$one->in_subtest, "no subtest_id by default");
};

tests api1 => sub {
    ok(!$one->causes_fail, "Events do not cause failures by default");
    is($one->terminate, undef, "terminate is undef by default");
    ok(!$one->global, "global is false by default");
    is($one->summary, 'My::MockEvent', "Default summary is event package");
    ok(!$one->nested, "not nested by default");
};

print STDERR <<EOT;

*********************************************************************
*********************************************************************
*********************************************************************

FIX ME! FIX ME!
FIX ME! FIX ME!
FIX ME! FIX ME!
FIX ME! FIX ME!
FIX ME! FIX ME!
FIX ME! FIX ME!
You need to test the new Event.pm

*********************************************************************
*********************************************************************
*********************************************************************
EOT

done_testing;

__END__


