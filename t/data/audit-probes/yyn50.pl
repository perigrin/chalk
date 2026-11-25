my @lines = ("b 2", "a 1", "c 3"); my $out = ""; open(my $o, ">", \$out) or die; for (sort @lines) { my ($k, $v) = split; printf $o "%-2s|%2d\n", $k, $v } close $o; print $out;
