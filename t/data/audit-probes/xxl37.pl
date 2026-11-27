our $t = 0; sub add { $t += $_[0]; $t } my @l; for my $i (1..3) { push @l, add($i) } print "@l$t\n";
