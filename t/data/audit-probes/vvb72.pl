my $t = 0; for my $i (1..3) { my $x = $i; my $inc = sub { $x++ }; $inc->() for 1..$i; $t += $x } print "$t\n";
