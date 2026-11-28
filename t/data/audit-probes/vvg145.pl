my $x = 1; my $r = \$x; my $q = \$x; print $r == $q ? "same" : "diff", "\n";
