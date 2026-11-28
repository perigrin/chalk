my @a = (1,2,3); sub f { my ($v) = @_; $v } my $t = 0; for my $x (@a) { my $y = $x * 2; $t += f($y) } print "$t\n";
