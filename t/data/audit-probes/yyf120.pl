my $s=""; for my $i (1..3) { my %t; $t{$i}=1; $s .= scalar(keys %t) } print "$s\n";
