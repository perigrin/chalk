our $g = 1; sub f { local $g = 2; $g } my $v = f() + f() + $g; print "$v\n";
