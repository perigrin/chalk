my @a=(1,2,3); sub z { $_[0][2]=10 } my $t=0; for my $x (@a) { $t+=$x; z(\@a) } print "$t\n";
