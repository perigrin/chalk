our %h; sub add { $h{$_[0]} = 1 } my $s = ""; for my $i (1..3) { add($i); $s .= scalar(keys %h) } print "$s\n";
