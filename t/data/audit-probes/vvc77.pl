our $x = 1; my $y = 5; *x = \$y; undef $x; print defined $y ? "d" : "u", "\n";
