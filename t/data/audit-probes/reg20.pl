our $g=1; sub f { $g=5; 1 } my $v = $g x f() . $g; print "$v\n";
