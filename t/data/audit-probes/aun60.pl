my $o = {}; my @r; for my $i (1..2) { push @r, ref($o); bless $o, "K$i" } print "@r ", ref($o), "\n";
