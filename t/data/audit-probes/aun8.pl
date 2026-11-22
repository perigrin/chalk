our $g = 0; sub bump { $g += 10 } my $f = \&bump; for (1..3) { $g++; $f->() } print "$g\n";
