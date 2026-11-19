our $g = 1; sub show { print "s$g\n" } for my $i (1..3) { local $g = $g + $i; if ($i == 2) { show(); last } show(); } print "$g\n";
