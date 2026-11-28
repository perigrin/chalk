my $s = ""; for my $i (1..3) { my @a; $s .= scalar(@a); push @a, $i; my $c = sub { @a } } print "$s\n";
