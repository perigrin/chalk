my @a = (1..5); my $s = 0; do { $s += shift @a } until @a < 3; print "$s @a\n";
