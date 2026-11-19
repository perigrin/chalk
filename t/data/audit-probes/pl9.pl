our $g = 0; my $f = sub { $g += 10 }; for my $i (1..3) { $g = $g + 1; $f->(); } print "$g\n";
