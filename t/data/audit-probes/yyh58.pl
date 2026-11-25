my @a = (5,6,7); my $x = shift(@a) + shift(@a); my $y = pop(@a) . scalar(@a); my @e; my $z = shift @e; my $w = pop @e; print "$x$y", defined $z ? "d" : "u", defined $w ? "d" : "u", "\n";
