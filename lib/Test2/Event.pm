package Test2::Event;
use strict;
use warnings;

our $VERSION = '1.302077';

use Carp();
use Test2::Util();
use Test2::Util::Trace();

use Test2::Util::HashBase(qw{
    trace
    -spec_version
    nested nest_parent nest_id nest_events -nest_buffered
    -terminate -global -stop_everything
    -causes_fail
    -summary -gravity
    -assertion -assertion_pass -assertion_skipped -assertion_no_debug
    assertion_amnesty nest_amnesty
    -plan -plan_info
    -diag -diag_data
    -_orig
});

# We eventually want to stop supporting this state modification.
Test2::Util::deprecate_quietly(qw{ set_trace set_nested });

use Test2::Util::ExternalMeta qw/meta get_meta set_meta delete_meta/;

sub CURRENT_SPEC_VERSION() { 1 }

{
    my $ID = 1;
    sub GEN_UNIQUE_NEST_ID { join "-" => ('NEST-ID', time(), $$, Test2::Util::get_tid, $ID++) }
}

sub init {
    my $self = shift;

    $self->{+NEST_PARENT} ||= delete $self->{in_subtest} if defined $self->{in_subtest};
    $self->{+NEST_ID}     ||= delete $self->{subtest_id} if defined $self->{subtest_id};
    $self->{+NEST_EVENTS} ||= delete $self->{subevents}  if defined $self->{subevents};
}

sub callback { }

sub related {
    my $self = shift;
    my ($event) = @_;

    my $tracea = $self->trace  or return undef;
    my $traceb = $event->trace or return undef;

    my $siga = $tracea->signature or return undef;
    my $sigb = $traceb->signature or return undef;

    return 1 if $siga eq $sigb;
    return 0;
}

sub amnesty {
    my $self = shift;
    return $self->assertion_amnesty || $self->nest_amnesty;
}

{
    no warnings 'redefine';

    sub causes_fail {
        my $self = shift;
        return $self->{+CAUSES_FAIL} if defined $self->{+CAUSES_FAIL};
        return 0 unless $self->assertion;
        return 0 if $self->amnesty;
        return 0 if $self->assertion_skipped;
        return $self->assertion_pass ? 1 : 0;
    }

    sub summary {
        my $self = shift;
        return $self->{+SUMMARY} if defined $self->{+SUMMARY};
        return ref($self);
    }

    sub gravity {
        my $self = shift;
        return $self->{+GRAVITY} if defined $self->{+GRAVITY};
        return 100 if $self->causes_fail && !$self->amnesty;
        return 0;
    }
}

# JSON
###############
sub from_json {
    my $class = shift;
    my %p     = @_;

    my $event_pkg = delete $p{'__PACKAGE__'};
    require(Test2::Util::pkg_to_file($event_pkg));

    if (exists $p{trace}) {
        $p{trace} = Test2::Util::Trace->from_json(%{$p{trace}});
    }

    if (exists $p{+NEST_EVENTS}) {
        my @subevents;
        for my $subevent (@{delete $p{+NEST_EVENTS} || []}) {
            push @subevents, Test2::Event->from_json(%$subevent);
        }
        $p{+NEST_EVENTS} = \@subevents;
    }

    return $event_pkg->new(%p);
}

{
    no warnings 'once';
    *to_json = \&TO_JSON;
}
sub TO_JSON {
    my $self = shift;

    my %overrides = @_;

    return {
        %$self,
        __PACKAGE__ => ref($self),

        Test2::Util::ExternalMeta::META_KEY() => undef,

        %overrides,
    };
}

# Legacy
###############

sub new_from_legacy {
    my $class = shift;
    my ($orig, %override) = @_;
    my $from = $orig->spec_version || 0;

    die "This is still a work in progress, and may not even be needed";

    # Set up initial state
    my $fields = {
        _orig => $orig,

        Test2::Util::ExternalMeta::META_KEY() => $orig->{Test2::Util::ExternalMeta::META_KEY()},

        (
            map { $orig->can($_) ? ($_ => $orig->$_) : () } (
                TRACE(),
                NESTED(),    NEST_PARENT(), NEST_ID(),     NEST_EVENTS(),
                TERMINATE(), GLOBAL(),      CAUSES_FAIL(), STOP_EVERYTHING(),
                SUMMARY(),   GRAVITY(),
                ASSERTION(), ASSERTION_PASS(), ASSERTION_AMNESTY(),
                PLAN(),      PLAN_INFO(),
                DIAG(),      DIAG_DATA(),
            )
        ),

        %override,
    };

    # Upgrade from 0 to 1
    if ($from < 1) {
        $fields->{+SPEC_VERSION} = 1; # The new spec version

        $fields->{+NEST_PARENT} = $orig->in_subtest       unless defined $fields->{+NEST_PARENT};
        $fields->{+NEST_ID}     = $orig->subtest_id       unless defined $fields->{+NEST_ID};
        $fields->{+NEST_EVENTS} = $orig->subevents        unless defined $fields->{+NEST_EVENTS};
        $fields->{+ASSERTION}   = $orig->increments_count unless defined $fields->{+ASSERTION};

        if (my ($plan, $directive, $reason) = $orig->sets_plan) {
            $fields->{+PLAN}      = $plan      unless defined $fields->{+PLAN};
            $fields->{+PLAN_INFO} = $reason    unless defined $fields->{+PLAN_INFO};
        }

        unless (defined($fields->{+GRAVITY})) {
            # Theoretically these should never both be true... but someone may
            # have done something dumb, in which case set gravity to 100.
            $fields->{+GRAVITY} = -1  if $orig->no_display;
            $fields->{+GRAVITY} = 100 if $orig->diagnostics;
        }
    }

    # Add other upgrades later
    # if ($from < 2) { ... }

    return $class->new(%$fields);
}

   #############################
#   ##                       ##   #
#####  DEPRECATED BELOW HERE  #####
#   ##                       ##   #
   #############################

Test2::Util::deprecate_quietly(
    qw{
        in_subtest subtest_id subevents no_display diagnostics increments_count
        set_subevents
    }
);

# Deprecate these harder as they modify state that we forbid modification of
# with the new attributes.
#Test2::Util::deprecate(qw/set_in_subtest set_subtest_id set_subevents/);


sub in_subtest { $_[0]->nest_parent }
sub subtest_id { $_[0]->nest_id }
sub subevents  { $_[0]->nest_events }

sub no_display  { $_[0]->gravity < 0 ? 1 : 0 }
sub diagnostics { $_[0]->gravity > 0 ? 1 : 0 }

sub increments_count { defined($_[0]->assertion) ? 1 : 0 }

sub sets_plan {
    my $self = shift;
    my $plan = $self->plan;
    return unless defined $plan;

    return (0, 'SKIP', $self->plan_info) if $plan eq 'SKIP';
    return ($plan);
}

sub set_in_subtest { $_[0]->{+NEST_PARENT} = $_[1] }
sub set_subtest_id { $_[0]->{+NEST_ID}     = $_[1] }
sub set_subevents  { $_[0]->{+NEST_EVENTS} = $_[1] }


1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Test2::Event - Base class for events

=head1 DESCRIPTION

Base class for all event objects that get passed through
L<Test2>.

=head1 EVENT API

The current event API specification version is 1.

=head2 CONTEXTUAL

=over 4

=item $trace = $e->trace()

This will return the L<Test2::Util::Trace> object from the events creation.
This MAY be undef. The trace typically points to the location in a test file
that ultimately produced the event.

=item $bool = $e->related($e2)

This checks if two events are related. Essentially this is just a check that
both share an identical trace. This can be used to pair an OK with a DIAG in
cases where they are separate events instead of a single event.

=back

=head2 NESTING

=over 4

=item $depth = $e->nested

This will normally be C<0> or C<undef>, both should be treated the same. When
the event is inside nesting (such as a subtest) however, this should be set to
the depth of the nesting.

=item $parent_id = $e->nest_parent

If this event is nested this should be set to the ID of the parent event. The
Event API specification does not enforce any format for these id's, except that
they must be strings.

Generating a unique ID can be difficult, specially if your test uses threads or
forks. See the L<< $e->GEN_UNIQUE_NEST_ID() >> method if you do not want to be
troubled to write your own ID generator.

=item $nest_id = $e->nest_id

If this event has nested events this should be set to the nesting ID.

=item $events = $e->nest_events

If this event has nested events than this should return an arrayref that
contains them. This MAY return C<undef>.

=item $bool_or_ref = $e->nest_amnesty

If the parent event has C<'assertion_amnesty'> set, this will hold the value.
This is an inherited amnesty as opposed to a direct amnesty.

=item $bool = $e->nest_buffered

This is true if the C<nest_events()> were buffered. When events are buffered it
means the formatter has not seen them yet, and should render them as part of
the main nest event (IE the event where C<nest_buffered()> is true). If this is
set to false then the events have already been seen once before in isolation.

=item $e->GEN_UNIQUE_NEST_ID

This method will return a unique nesting ID every time it is called. This will
never return the same one twice in a single test run. ID's are not guaranteed
to be unique between multiple runs, but they likely will be.

Currently the implementation is very simple:

    "NEST-ID-$UNIX_TIME-$PID-$TID-$SEQUENTIAL_NUMBER"

The ID starts with the "NEST-ID" string, followed by the timestamp as taken
from C<time()>, followed by the process id, then the thread id, and finally
ends with a sequential number that increments every call. Containing the PID,
TID, and a number that as incremented should ensure the ID is unique. Multiple
ID's can contain the same last number, but will have different process or
thread ids. The unix timestamp is simply added for good measure.

B<PLEASE NOTE>: The format returned by this method is subject to change.
NOTHING should rely on the format of these id's.

=back

=head2 ROUTING AND STATE MANAGEMENT

=over 4

=item $exit_val = $e->terminate

This method is a hook so that an event can tell the L<Test2::Hub> instance that
the test run should exit Immediately. If this returns a defined value the test
will call C<exit($exit_val)>. This will normally return C<undef> which tells
the hub not to exit.

=item $bool = $e->global

If this is set to true then the event will be sent to all hubs. Normally an
event only goes to a single destination hub.

=item $bool_or_ref = $e->stop_everything

If true all testing should stop. The currently running test file should stop. A
harness that recognises this type of event should stop all test files. In TAP
this is a bailout.

You may provide a human readable reason for the stop by assigning
C<stop_everything> a string reference. A reference is required to insure that
this method still returns true even if the reason is C<0> or C<''>.

The Test2 internals will C<ALWAYS> use this method as a boolean. Formatters
(including TAP) may choose to check for a reference for rendering purposes.

=item $bool = $e->causes_fail

If this is true the test run will be marked as a failure. This does NOT imply
that any assertions were made.

If you set this to a defined value at construction, it will always return that
value.

If you do not set this a default will be used. IF the event is an assertion
that failed without amnesty this will be set to TRUE, otherwise it will be set
to FALSE.

=item $e->callback($hub)

The callback is a hook that lets an event directly manipulate a hub. This is
rarely used. You must create a custom event subclass in order to provide a
callback.

=item $bool = $e->amnesty

This is a shortcut for C<< $bool_or_ref = $e->assertion_amnesty || $e->nest_amnesty; >>

=back

=head2 RENDERING

=over 4

=item $text = $e->summary

The summary should be a human readable string that BRIEFLY describe the event.
If no summary is set then the output of C<ref($e)> will be used.

=item $int = $e->gravity

The gravity of an event should be used by harnesses to determine if/when an
event should be displayed. This only matters for harnesses that have verbosity
levels. The value should be an integer.

A value less than C<0> means the event should never be displayed (internal
events).

A value of C<0> means the event has normal gravity and the formatter can hide
the event as nothing notable if it chooses.

A value greater than C<0> means the event is important and should be seen
depending on the verbosity.

Events will default to a gravity of C<0>. Events that cause a failure will
default to a gravity of C<100>.

=item $array_of_strings = $e->diag

Any event may have some diagnostics messaging for humans to read. If gravity is
0 a test harness may choose to hide the messages. If the gravity is higher the
harness should probably render the messages depending on its verbosity settings.

As an example, the TAP formatter sends this to STDERR if the gravity is greater
than 0 to insure the harness does not hide it.

=item $data = $e->diag_data

This follows all the rules C<diag()> does, but may contain a data structure
instead of a simple string. Be advised that if you put a blessed item in here
that does not have a TO_JSON method it can break serialization.

=back

=head2 ASSERTIONS

=over 4

=item $bool_or_ref = $e->assertion

This should be true if an assertion was made. Optionally the return may be a
reference to a string describing, naming, or otherwise identifying the
assertion. A ref is used instead of a plain string in case there is no
name/description/id associated with the assertion, in which case a simple true
value can be used.

The Test2 internals will C<ALWAYS> use this method as a boolean. Formatters
(including TAP) may choose to check for a reference for rendering purposes.

=item $bool = $e->assertion_pass

This should return true if the assertion passed, false if it failed.
C<causes_fail()> will consider this value when it is not given a value during
construction.

=item $bool_or_ref = $e->assertion_amnesty

If this is true then failure is accepted and allowed. Essentially if this is
true then a failed assertion should not cause the overall test run to fail.
This is how things like 'TODO' are implemented.

If you wish to provide a reason amnesty was granted you may do so by setting
the value of C<'assertion_amnesty'> to a scalar reference explaining the
amnesty. For example:

    my $reason = "Royal Pardon";

    my $event = Test2::Event->new(
        ...,
        assertion_amnesty => \$reason,
    );

The reason B<MUST> be provided as a reference. This decision was made largely
to support legacy code as C<0> and C<''> are perfectly valid TODO values in
legacy L<Test::Builder>, but would make this method return false.

The Test2 internals will C<ALWAYS> use this method as a boolean. Formatters
(including TAP) may choose to check for a reference for rendering purposes.

=item $bool_or_ref = $e->assertion_skipped

Sometimes an event is generated for an assertion that has been skipped (to
maintain a consistent assertion count). If this is set to a true value it means
the test was skipped. The true value may be a string reference, in which case
the string as assumed to be the reason the assertion was skipped.

=item $bool = $e->assertion_no_debug

Set this to true if you do not want formatters to automatically add debugging
info (file and line number, etc) output to failed assertions. Use this if your
tool will provide custom debug info either within this event itself, or in
another event.

=back

=head2 PLANNING

=over 4

=item $int = $e->plan

If this returns undef no plan is set by this event. If this returns 0 the event
is saying no tests should be run (skip-all). If this is set to a positive
integer than it is the expected number of assertions.

=item $info = $e->plan_info

If the plan is set to C<0> (IE no tests, or skip all) the C<plan_info()> may be
a human readable string explaining why.

=back

=head2 META-DATA FOR PLUGINS AND TOOLS

This class uses L<Test2::Util::ExternalMeta> which provides multiple methods
for setting meta-data. All meta-data is stripped away during JSON
serialization, none of it will ever reach the harness without a custom
renderer, or overrides to the C<TO_JSON> method.

=over 4

=item $val = $obj->meta($key)

=item $val = $obj->meta($key, $default)

This will get the value for a specified meta C<$key>. Normally this will return
C<undef> when there is no value for the C<$key>, however you can specify a
C<$default> value to set when no value is already set.

=item $val = $obj->get_meta($key)

This will get the value for a specified meta C<$key>. This does not have the
C<$default> overhead that C<meta()> does.

=item $val = $obj->delete_meta($key)

This will remove the value of a specified meta C<$key>. The old C<$val> will be
returned.

=item $obj->set_meta($key, $val)

Set the value of a specified meta C<$key>.

=back

=head2 SERIALIZATION

=over 4

=item $json_string = $e->TO_JSON

=item $json_string = $e->to_json

These are both aliases to the same thing. This will serialize the event as a
JSON string.

=item Test2::Event->from_json($json_string);

This will reconstruct an event from the JSON produced from C<to_json()>. This
will take care of re-blessing the event and trace objects.

=back

=head2 LEGACY SUPPORT

=over 4

=item $e = Test2::Event->new_from_legacy($e_legacy)

=item $e = Test2::Event->new_from_legacy($e_legacy, %overrides)

This will convert a legacy event (An event where C<spec_version()> returns less
than the current version) to a modern event.

This conversion is intended for formatters and harnesses so that they can
simplify around a single version of the event API. This should not be used to
produce or filter events before or inside a hub. In particular a C<callback()>
in the original will be missing from the new event.

=item $v = $e->spec_version

This should return the version of the Event API specification that the event
follows.

=back

=head2 DEPRECATED

=over 4

=item $bool = $e->no_display

This returns true if the event is internal and should not be displayed by a
renderer/harness.

This was deprecated by the C<gravity()> method. This method can be thought of
as C<< sub { $e->gravity < 0 } >>.

=item $bool = $e->diagnostics

This returns true if the event has important diagnostics info that the renderer
or harness should be sure to show.

This was deprecated by the C<gravity()> method. This method can be thought of
as C<< sub { $e->gravity > 0 } >>.

=item $id = $e->in_subtest

This was renamed to C<nest_parent()>.

=item $id = $e->subtest_id

This was renamed to C<nest_id()>.

=item $events = $e->subevents

This was renamed to C<nest_events()>.

=item $e->increments_count

This was renamed to C<assertion()>.

=item ($count, $directive, $reason) =  $e->sets_plan

This has been replaced by the C<plan()>, C<directive()>, and C<reason()>
methods.

=back

=head1 SOURCE

The source code repository for Test2 can be found at
F<http://github.com/Test-More/test-more/>.

=head1 MAINTAINERS

=over 4

=item Chad Granum E<lt>exodist@cpan.orgE<gt>

=back

=head1 AUTHORS

=over 4

=item Chad Granum E<lt>exodist@cpan.orgE<gt>

=back

=head1 COPYRIGHT

Copyright 2016 Chad Granum E<lt>exodist@cpan.orgE<gt>.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

See F<http://dev.perl.org/licenses/>

=cut
