my $t=""; for my $i (1..2) { my %h; $h{$i}=1; $t.=join(",", keys %h)."|" } print "$t\n";
