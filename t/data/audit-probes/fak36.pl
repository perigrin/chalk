my $x=0; my $inc=sub { $x++ }; my $t=0; while ($x<3) { $inc->(); $t+=$x } print "$t\n";
