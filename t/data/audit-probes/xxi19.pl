our $g1 = 1; our $g2 = 2; for my $n (qw(g1 g2)) { no strict 'refs'; $$n *= 10 } print "$g1 $g2\n";
