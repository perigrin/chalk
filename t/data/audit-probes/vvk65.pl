my $s = ""; for (1..3) { last if $_ == 2; $s .= $_ } continue { $s .= "c" } print "$s\n";
