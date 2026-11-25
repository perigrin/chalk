my $x = 5; my $r = \$x; my $rr = \$r; $$$rr++; my @a = (\$x, \$x); ${$a[1]} *= 2; print "$x ", $a[0] == $a[1] ? "same" : "diff", "\n";
