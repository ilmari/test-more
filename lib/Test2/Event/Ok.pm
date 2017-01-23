package Test2::Event::Ok;
use strict;
use warnings;

our $VERSION = '1.302077';

BEGIN { require Test2::Event; our @ISA = qw(Test2::Event) }
use Test2::Util::HashBase qw{
    pass effective_pass name
};

sub init {
    my $self = shift;

    $self->SUPER::init();

    $self->{+ASSERTION_AMNESTY} ||= \($self->{todo})
        if defined $self->{todo};

    # Legacy support
    $self->{todo} = ${$self->{+ASSERTION_AMNESTY}} if ref $self->{+ASSERTION_AMNESTY};

    # Do not store objects here, only true or false
    $self->{+PASS} = $self->{+PASS} ? 1 : 0;
    $self->{+EFFECTIVE_PASS} = $self->{+PASS} || (defined($self->{+ASSERTION_AMNESTY}) ? 1 : 0);
}

sub default_name       { "Nameless Assertion" }
sub spec_version       { 1 }
sub causes_fail        { !$_[0]->{+EFFECTIVE_PASS} }
sub assertion          { my $str = $_[0]->{+NAME}; $str ? \$str : 1 }
sub assertion_pass     { $_[0]->{+PASS} }
sub assertion_no_debug { 1 }

sub assertion_amnesty {
    my $self = shift;
    my $amnesty = $self->{+ASSERTION_AMNESTY};
    return $amnesty if defined $amnesty;
    return undef if $self->{+PASS};
    return $self->{+EFFECTIVE_PASS};
}

sub set_assertion_amnesty {
    my $self = shift;
    my ($bool_or_ref) = @_;
    $self->{+ASSERTION_AMNESTY} = $bool_or_ref;
    $self->{+EFFECTIVE_PASS} = $bool_or_ref ? 1 : $self->{+PASS};
    $self->{todo} = $$bool_or_ref if ref($bool_or_ref);
}

sub set_nest_amnesty {
    my $self = shift;
    my ($bool_or_ref) = @_;
    $self->{+NEST_AMNESTY} = $bool_or_ref;
    $self->{+EFFECTIVE_PASS} = $bool_or_ref ? 1 : $self->{+PASS};
}

sub todo {
    my $self     = shift;
    my $todo_ref = $self->{+ASSERTION_AMNESTY};
    return undef unless ref($todo_ref);
    return $$todo_ref;
}

{
    no warnings 'redefine';

    sub set_effective_pass {
        my $self = shift;
        my ($bool) = @_;

        if ($bool) {
            $self->set_assertion_amnesty($bool) unless $self->assertion_amnesty;
        }
        else {
            $self->set_assertion_amnesty($bool);
        }

        # Set exact value, as requested
        $self->{+EFFECTIVE_PASS} = $bool;
    }
}

sub set_todo {
    my $self = shift;
    my ($todo) = @_;

    if (defined($todo)) {
        $self->set_assertion_amnesty(\$todo);
    }
    else {
        $self->set_assertion_amnesty(0);
    }
}

sub summary {
    my $self = shift;

    my $name = $self->{+NAME} || $self->default_name;

    my $todo = $self->todo;
    if ($todo) {
        $name .= " (TODO: $todo)";
    }
    elsif (defined $todo) {
        $name .= " (TODO)";
    }

    return $name;
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Test2::Event::Ok - Ok event type

=head1 DESCRIPTION

Ok events are generated whenever you run a test that produces a result.
Examples are C<ok()>, and C<is()>.

=head1 SYNOPSIS

    use Test2::API qw/context/;
    use Test2::Event::Ok;

    my $ctx = context();
    my $event = $ctx->ok($bool, $name, \@diag);

or:

    my $ctx   = context();
    my $event = $ctx->send_event(
        'Ok',
        pass => $bool,
        name => $name,
    );

=head1 ACCESSORS

=over 4

=item $rb = $e->pass

The original true/false value of whatever was passed into the event (but
reduced down to 1 or 0).

=item $name = $e->name

Name of the test.

=item $b = $e->effective_pass

This is the true/false value of the test after TODO and similar modifiers are
taken into account.

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
