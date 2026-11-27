our $t = 0; sub add { $t += $_[0]; $t } my @l = map { add($_) + $t } 1..3; print "@l\n";
