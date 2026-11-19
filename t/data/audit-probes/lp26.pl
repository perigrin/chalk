my $i = 0; my $s = 0; AGAIN: $s += $i; $i++; goto AGAIN if $i < 4; print "$s\n";
