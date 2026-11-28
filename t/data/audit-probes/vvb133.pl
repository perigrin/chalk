my $s = ""; for my $i (1..3) { my $x; $s .= defined $x ? "d" : "u"; $x = $i; my $r = \$x } print "$s\n";
