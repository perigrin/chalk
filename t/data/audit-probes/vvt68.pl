sub f { $_[0]++ } my $t = 0; my $i = 0; do { my $y = $i; f($y); $t += $y } while ($i++ < 2); print "$t\n";
