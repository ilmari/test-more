package Test2::Event::Subtest;
use strict;
use warnings;

our $VERSION = '1.302077';

BEGIN { require Test2::Event::Ok; our @ISA = qw(Test2::Event::Ok) }
use Test2::Util::HashBase;

sub default_name { "Nameless Subtest" }

sub init {
    my $self = shift;

    $self->SUPER::init();

    $self->{+NEST_EVENTS} ||= delete $self->{subevents} || [];
    $self->{+NEST_BUFFERED} ||= delete $self->{buffered};

    # Legacy
    $self->{subevents} = $self->{+NEST_EVENTS};
    $self->{buffered}  = $self->{+NEST_BUFFERED};

    if (my $amnesty = $self->amnesty) {
        $_->set_nest_amnesty($amnesty) for @{$self->{+NEST_EVENTS}};
    }
}

sub buffered { $_[0]->{+NEST_BUFFERED} }
sub set_buffered { $_[0]->{+NEST_BUFFERED} = $_[0]->{buffered} = $_[1] }

sub set_nest_events {
    my $self = shift;
    my ($events) = @_;

    $self->{+NEST_EVENTS} = $events;

    # Legacy
    $self->{subevents} = $self->{+NEST_EVENTS};

    if (my $amnesty = $self->amnesty) {
        $_->set_nest_amnesty($amnesty) for @{$self->{+NEST_EVENTS}};
    }
}

sub set_assertion_amnesty {
    my $self = shift;
    my ($bool_or_ref) = @_;

    $self->SUPER::set_assertion_amnesty($bool_or_ref);

    $_->set_nest_amnesty($self->amnesty) for @{$self->{+NEST_EVENTS}};
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Test2::Event::Subtest - Event for subtest types

=head1 DESCRIPTION

This class represents a subtest. This class is a subclass of
L<Test2::Event::Ok>.

=head1 ACCESSORS

This class inherits from L<Test2::Event::Ok>.

=over 4

=item $arrayref = $e->subevents

Returns the arrayref containing all the events from the subtest

=item $bool = $e->buffered

True if the subtest is buffered, that is all subevents render at once. If this
is false it means all subevents render as they are produced.

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
