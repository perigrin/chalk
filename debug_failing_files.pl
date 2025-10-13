#!/usr/bin/env perl
# ABOUTME: Deep debugging script to analyze parser failures in baseline files
# ABOUTME: Shows exact location and context of parse failures
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my @failing_files = (
    'lib/Chalk/Grammar/Perl.pm',
    'lib/Chalk/Parser.pm',
    'lib/Chalk/Preprocessor/Heredoc.pm',
    'lib/Chalk/Semiring/Composite.pm',
    'lib/Chalk/Semiring/SPPF.pm',
);

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

for my $file (@failing_files) {
    print "=" x 80, "\n";
    print "FILE: $file\n";
    print "=" x 80, "\n";

    open my $fh, '<', $file or die "Can't open $file: $!";
    my $code = do { local $/; <$fh> };
    close $fh;

    my $length = length($code);

    # Capture parsing failure position
    local $SIG{__WARN__} = sub {
        my $msg = shift;
        if ($msg =~ /PARSING STOPPED: Reached position (\d+) of (\d+)/) {
            my ($pos, $total) = ($1, $2);

            # Show context around failure point
            my $context_size = 100;
            my $start = $pos > $context_size ? $pos - $context_size : 0;
            my $end = $pos + $context_size < $total ? $pos + $context_size : $total;

            my $before = substr($code, $start, $pos - $start);
            my $at = substr($code, $pos, 1);
            my $after = substr($code, $pos + 1, $end - $pos - 1);

            # Find line number
            my $before_text = substr($code, 0, $pos);
            my $line_num = 1 + ($before_text =~ tr/\n/\n/);
            my @lines = split /\n/, $before_text;
            my $current_line = $lines[-1] // '';

            print "\nFailed at position $pos of $total (",
                  sprintf("%.1f%%", 100 * $pos / $total), ")\n";
            print "Line number: $line_num\n";
            print "Current line: $current_line\n";
            print "\nContext (showing ±$context_size chars):\n";
            print "-" x 80, "\n";
            print "BEFORE: ", _escape($before), "\n";
            print "AT--->: [", _escape($at), "]\n";
            print "AFTER:  ", _escape($after), "\n";
            print "-" x 80, "\n";

            # Try to identify what construct is being parsed
            my $snippet = substr($code, $pos - 50 > 0 ? $pos - 50 : 0, 100);
            print "\nSnippet around failure:\n";
            print _escape($snippet), "\n";
        }
    };

    my $result = $parser->parse_string($code);

    print "\n";
}

sub _escape {
    my $str = shift;
    $str =~ s/\n/\\n/g;
    $str =~ s/\t/\\t/g;
    return $str;
}
