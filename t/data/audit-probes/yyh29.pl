sub f { my @e; return @e } sub g { return () } sub h { return } my $s=f(); my $t=g(); my @l=(g(),1,h()); print defined $s ? "d$s" : "u", defined $t ? "d" : "u", scalar(@l), "\n";
