our $g = 0; sub bump { $g += 10; 1 } for (1..3) { $g++; my $x = bump() ? $g : 0; print "$x " } print "$g\n";
