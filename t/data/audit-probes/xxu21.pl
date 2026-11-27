our $x = 1; sub c { $x = 3; 2 } my $s = ""; for my $v ($x, c()) { $s .= $v } print "$s\n";
