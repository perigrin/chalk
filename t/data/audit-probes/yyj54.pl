my $s = ""; for (1..2) { $s .= join "", map { $_ * 2 } grep { $_ } 0..$_ } print "$s\n";
