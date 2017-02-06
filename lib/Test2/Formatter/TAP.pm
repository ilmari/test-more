package Test2::Formatter::TAP;
use strict;
use warnings;
require PerlIO;

our $VERSION = '1.302077';

use Carp qw/confess/;
use Test2::Util::HashBase qw{ no_numbers handles _encoding };

sub OUT_STD() { 0 }
sub OUT_ERR() { 1 }

sub hide_buffered { 1 }

BEGIN { require Test2::Formatter; our @ISA = qw(Test2::Formatter) }

_autoflush(\*STDOUT);
_autoflush(\*STDERR);

sub init {
    my $self = shift;

    $self->{+HANDLES} ||= $self->_open_handles;
    if(my $enc = delete $self->{encoding}) {
        $self->encoding($enc);
    }
}

sub encoding {
    my $self = shift;

    if (@_) {
        my ($enc) = @_;
        my $handles = $self->{+HANDLES};

        # https://rt.perl.org/Public/Bug/Display.html?id=31923
        # If utf8 is requested we use ':utf8' instead of ':encoding(utf8)' in
        # order to avoid the thread segfault.
        if ($enc =~ m/^utf-?8$/i) {
            binmode($_, ":utf8") for @$handles;
        }
        else {
            binmode($_, ":encoding($enc)") for @$handles;
        }
        $self->{+_ENCODING} = $enc;
    }

    return $self->{+_ENCODING};
}

sub _open_handles {
    my $self = shift;

    my %seen;
    open(my $out, '>&', STDOUT) or die "Can't dup STDOUT:  $!";
    binmode($out, join(":", "", "raw", grep { $_ ne 'unix' and !$seen{$_}++ } PerlIO::get_layers(STDOUT)));

    %seen = ();
    open(my $err, '>&', STDERR) or die "Can't dup STDERR:  $!";
    binmode($err, join(":", "", "raw", grep { $_ ne 'unix' and !$seen{$_}++ } PerlIO::get_layers(STDERR)));

    _autoflush($out);
    _autoflush($err);

    return [$out, $err];
}

sub _autoflush {
    my($fh) = pop;
    my $old_fh = select $fh;
    $| = 1;
    select $old_fh;
}

if ($^C) {
    no warnings 'redefine';
    *write = sub {};
}
sub write {
    my ($self, $e, $num) = @_;

    my @tap = $self->event_tap($e, $num);

    my $handles = $self->{+HANDLES};
    my $nesting = $e->nested || 0;
    my $indent = '    ' x $nesting;

    # Local is expensive! Only do it if we really need to.
    local($\, $,) = (undef, '') if $\ || $,;
    for my $set (@tap) {
        no warnings 'uninitialized';
        my ($hid, $msg) = @$set;
        next unless $msg;
        my $io = $handles->[$hid] or next;

        $msg =~ s/^/$indent/mg if $nesting;
        print $io $msg;
    }
}

sub event_tap {
    my ($self, $e, $num) = @_;

    my $no_summary = 0;
    my @tap;

    # If this IS the first event the plan should come first
    # (plan must be before or after assertions, not in the middle)
    ++$no_summary && push @tap => $self->plan_tap($e) if $num == 1 && defined $e->plan;

    # The assertion is most important, if present.
    if ($e->assertion) {
        ++$no_summary;
        push @tap => $self->assertion_tap($e, $num);
        push @tap => $self->debug_tap($e, $num) unless $e->assertion_no_debug || $e->assertion_pass;
    }

    # Now lets see the diagnostics messages
    ++$no_summary && push @tap => $self->diag_tap($e)      if $e->diag;
    ++$no_summary && push @tap => $self->diag_data_tap($e) if $e->diag_data;

    # If this IS NOT the first event the plan should come last
    # (plan must be before or after assertions, not in the middle)
    ++$no_summary && push @tap => $self->plan_tap($e) if $num != 1 && defined $e->plan;

    # Bail out
    ++$no_summary && push @tap => $self->bail_tap($e) if $e->stop_everything;

    # Use the summary as a fallback if nothing else is usable.
    push @tap => $self->summary_tap($e, $num) unless $no_summary || @tap;

    return @tap;
}

sub plan_tap {
    my $self = shift;
    my ($e) = @_;
    my $plan = $e->plan;
    return if $plan eq 'NO PLAN';

    if ($plan eq 'SKIP') {
        my $reason = $e->plan_info or return [OUT_STD, "1..0 # SKIP\n"];
        chomp($reason);
        return [OUT_STD, '1..0 # SKIP ' . $reason . "\n"];
    }

    return [OUT_STD, "1..$plan\n"];

    return;
}

sub no_subtest_space { 0 }

sub assertion_tap {
    my $self = shift;
    my ($e, $num) = @_;

    my $assertion = $e->assertion;
    my $name = ref($assertion) ? $$assertion : undef;
    my $pass = $e->assertion_pass;
    my $in_todo = $e->assertion_amnesty;
    my $skipped = $e->assertion_skipped;

    my $ok = "";
    $ok .= "not " unless $pass;
    $ok .= "ok";
    $ok .= " $num" unless $self->{+NO_NUMBERS};

    # The regex form is ~250ms, the index form is ~50ms
    my @extra;
    defined($name) && (
        (index($name, "\n") != -1 && (($name, @extra) = split(/\n\r?/, $name, -1))),
        ((index($name, "#" ) != -1  || substr($name, -1) eq '\\') && (($name =~ s|\\|\\\\|g), ($name =~ s|#|\\#|g)))
    );

    my $extra_space = @extra ? ' ' x (length($ok) + 2) : '';
    my $extra_indent = '';

    $ok .= " - $name" if defined $name && !($skipped && !$name);

    my @subtap;
    if ($e->nest_id && $e->nest_buffered) {
        $ok .= ' {';

        # In a verbose harness we indent the extra since they will appear
        # inside the subtest braces. This helps readability. In a non-verbose
        # harness we do not do this because it is less readable.
        if ($ENV{HARNESS_IS_VERBOSE} || !$ENV{HARNESS_ACTIVE}) {
            $extra_indent = "    ";
            $extra_space = ' ';
        }

        # Render the sub-events, we use our own counter for these.
        my $count = 0;
        @subtap = map {
            # Bump the count for any event that should bump it.
            $count++ if $_->assertion;

            # This indents all output lines generated for the sub-events.
            # index 0 is the filehandle, index 1 is the message we want to indent.
            map { $_->[1] =~ s/^(.*\S.*)$/    $1/mg; $_ } $self->event_tap($_, $count);
        } @{$e->nest_events};

        push @subtap => [OUT_STD, "}\n"];
    }

    if($skipped) {
        if ($in_todo) {
            use Data::Dumper;
            print Dumper($e);
            $ok .= " # TODO & SKIP";
        }
        else {
            $ok .= " # skip";
        }
        $ok .= " $$skipped" if ref($skipped) && length($$skipped);
    }
    elsif ($in_todo) {
        $ok .= " # TODO";
        $ok .= " $$in_todo" if ref($in_todo) && length($$in_todo);
    }

    $extra_space = ' ' if $self->no_subtest_space;

    my @out = ([OUT_STD, "$ok\n"]);
    push @out => map {[OUT_STD, "${extra_indent}#${extra_space}$_\n"]} @extra if @extra;
    push @out => @subtap;

    return @out;
}

sub debug_tap {
    my ($self, $e, $num) = @_;

    # This behavior is inherited from Test::Builder which injected a newline at
    # the start of the first diagnostics when the harness is active, but not
    # verbose. This is important to keep the diagnostics from showing up
    # appended to the existing line, which is hard to read. In a verbose
    # harness there is no need for this.
    my $prefix = $ENV{HARNESS_ACTIVE} && !$ENV{HARNESS_IS_VERBOSE} ? "\n" : "";

    # Figure out the debug info, this is typically the file name and line
    # number, but can also be a custom message. If no trace object is provided
    # then we have nothing useful to display.
    my $name  = $e->name;
    my $trace = $e->trace;
    my $debug = $trace ? $trace->debug : "[No trace info available]";

    # Create the initial diagnostics. If the test has a name we put the debug
    # info on a second line, this behavior is inherited from Test::Builder.
    my $msg = defined($name)
        ? qq[# ${prefix}Failed test '$name'\n# $debug.\n]
        : qq[# ${prefix}Failed test $debug.\n];

    my $IO = $e->amnesty ? OUT_STD : OUT_ERR;

    return [$IO, $msg];
}

sub diag_tap {
    my ($self, $e) = @_;

    my $diag = $e->diag or return;

    confess "Got non-arrayref diag in event '$e'"
        unless ref($diag) eq 'ARRAY';

    my $IO = $e->gravity > 0 ? OUT_ERR : OUT_STD;

    return map {
        chomp(my $msg = $_);
        $msg =~ s/^/# /;
        $msg =~ s/\n/\n# /g;
        [$IO, "$msg\n"];
    } @$diag;
}

sub diag_data_tap {
    my ($self, $e) = @_;

    my $data = $e->diag_data or return;

    my $IO = $e->gravity > 0 ? OUT_ERR : OUT_STD;

    require Data::Dumper;
    my $dumper = Data::Dumper->new([$data])->Indent(2)->Terse(1)->Pad('# ')->Useqq(1)->Sortkeys(1);
    my $out = $dumper->Dumper;

    [$IO, $dumper->Dump];
}

sub bail_tap {
    my ($self, $e) = @_;

    return if $e->nested;
    my $stop = $e->stop_everything or return;

    return [OUT_STD, "Bail out!\n"] unless ref $stop;
    return [OUT_STD, "Bail out!  $$stop\n"];
}

sub summary_tap {
    my ($self, $e, $num) = @_;

    return if $e->gravity < 0;

    my $summary = $e->summary or return;
    chomp($summary);
    $summary =~ s/^/# /smg;

    my $IO = $e->gravity > 0 ? OUT_ERR : OUT_STD;

    return [$IO, "$summary\n"];
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Test2::Formatter::TAP - Standard TAP formatter

=head1 DESCRIPTION

This is what takes events and turns them into TAP.

=head1 SYNOPSIS

    use Test2::Formatter::TAP;
    my $tap = Test2::Formatter::TAP->new();

    # Switch to utf8
    $tap->encoding('utf8');

    $tap->write($event, $number); # Output an event

=head1 METHODS

=over 4

=item $bool = $tap->no_numbers

=item $tap->set_no_numbers($bool)

Use to turn numbers on and off.

=item $arrayref = $tap->handles

=item $tap->set_handles(\@handles);

Can be used to get/set the filehandles. Indexes are identified by the
C<OUT_STD> and C<OUT_ERR> constants.

=item $encoding = $tap->encoding

=item $tap->encoding($encoding)

Get or set the encoding. By default no encoding is set, the original settings
of STDOUT and STDERR are used.

This directly modifies the stored filehandles, it does not create new ones.

=item $tap->write($e, $num)

Write an event to the console.

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

=item Kent Fredric E<lt>kentnl@cpan.orgE<gt>

=back

=head1 COPYRIGHT

Copyright 2016 Chad Granum E<lt>exodist@cpan.orgE<gt>.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

See F<http://dev.perl.org/licenses/>

=cut
