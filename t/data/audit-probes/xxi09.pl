our $g = 1; my $n = "g"; { no strict 'refs'; $$n = 5; } print "$g\n";
