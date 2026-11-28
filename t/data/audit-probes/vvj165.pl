my @a = (1,2,3); sub ret { wantarray ? @a : scalar(@a) } my @l = ret(); my $s = ret(); my ($f) = ret(); print "@l$s$f\n";
