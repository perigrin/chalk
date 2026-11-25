my $v = eval { 5 }; my @l = eval { (1,2,3) }; my $ok = eval { die "x\n"; 1 }; my $u = eval { undef } // "u"; my $r = eval { return 7; 8 }; print "$v@l", defined $ok ? "d" : "u", "$u$r\n";
